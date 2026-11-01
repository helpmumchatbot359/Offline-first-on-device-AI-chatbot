// Tests for the telemetry rules about the retrieval tool:
//
//  RULE 1  Model requests/executes the tool            -> metadata.tool_used = true
//  RULE 2  Tool was used                               -> metadata.retrieved_passage_count = number of
//                                                         passages used (0 when the tool found nothing)
//  RULE 3  Tool execution fails                        -> outcome "error", error_code "TOOL_ERROR",
//                                                         metadata.error_stage "tool_execution",
//                                                         and metadata.tool_used stays true
//  RULE 4  A setup problem (e.g. contract file missing) -> NO tool ran, so it must NOT be TOOL_ERROR
//
// Run with:   flutter test test/telemetry_tool_alignment_test.dart
//
// If the imports below are red, replace "mama_ai" with the `name:` at the top of your pubspec.yaml.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/ai/native_offline_ai_service.dart';
import 'package:mama_ai/features/chat/data/chat_repository_impl.dart';
import 'package:mama_ai/features/chat/data/local/entities/local_telemetry_entity.dart';
import 'package:mama_ai/features/chat/data/telemetry/telemetry_recorder.dart';

/// Plays Android's events through the SAME code the app uses to collect measurements.
OfflineRun play(List<Map<String, dynamic>> events) {
  final run = OfflineRun();
  run.clock.start();
  run.stage = 'generation'; // the app is in this stage when generate() starts
  for (final map in events) {
    run.observe(AiEvent.fromMap(map));
  }
  return run;
}

/// Builds the offline_inference event the same way the app does, so we can validate it.
LocalTelemetryEvent inferenceEvent(
  OfflineRun run, {
  required String outcome,
  String? code,
  String? stage,
}) =>
    LocalTelemetryEvent(
      eventUuid: 'event-test',
      eventType: TelemetryContract.offlineInference,
      chatId: 'chat-1',
      date: DateTime.now().toUtc().toIso8601String(),
      modelVersion: TelemetryContract.modelVersion,
      latencyMs: 1500,
      outcome: outcome,
      errorCode: code,
      connectivity: 'offline',
      metadataJson: jsonEncode({'error_stage': stage, ...run.responseMetadata()}),
      syncState: 'pending',
    );

/// Mirrors what ChatRepositoryImpl does at the end of one request.
/// Returns null when the failure would be stored as a runtime_failure instead.
LocalTelemetryEvent? finishRequest(OfflineRun run, {Object? thrown, bool cancelled = false}) {
  var failure = thrown == null ? null : ChatRepositoryImpl.classifyOfflineError(thrown, run);
  failure = ChatRepositoryImpl.finalFailure(cancelled: cancelled, failure: failure, run: run);
  if (cancelled) return inferenceEvent(run, outcome: 'cancelled', code: 'CANCELLED', stage: run.stage);
  if (failure == null) return inferenceEvent(run, outcome: 'success');
  if (failure.inferenceCode != null) {
    return inferenceEvent(run, outcome: 'error', code: failure.inferenceCode, stage: failure.stage);
  }
  return null;
}

Map<String, dynamic> meta(LocalTelemetryEvent e) => jsonDecode(e.metadataJson) as Map<String, dynamic>;

void main() {
  group('RULE 1 + 2: successful requests', () {
    test('T1  tool used, 2 passages -> tool_used true, count 2', () {
      final run = play([
        {'event': 'started'},
        {'event': 'tool_call_requested'},
        {'event': 'retrieval_context', 'citations': [{}, {}], 'context_ids': ['record-1', 'record-2']},
        {'event': 'tool_result', 'tool_used': true, 'retrieved_passage_count': 2, 'tool_error': false},
        {'event': 'token', 'text': 'Hello'},
        {'event': 'completed', 'tool_used': true, 'retrieved_passage_count': 2, 'tool_error': false},
      ]);
      final e = finishRequest(run)!;
      expect(e.outcome, 'success');
      expect(meta(e)['tool_used'], true);
      expect(meta(e)['retrieved_passage_count'], 2);
      expect(TelemetryContract.validate(e), isEmpty);
    });

    test('T2  retrieval_context alone is counted (Android sends "citations", not "passages")', () {
      final run = play([
        {'event': 'tool_call_requested'},
        {'event': 'retrieval_context', 'citations': [{}], 'context_ids': ['record-9']},
      ]);
      expect(run.retrievedPassageCount, 1);
    });

    test('T3  tool found NOTHING -> count is 0 and the key is still present', () {
      final run = play([
        {'event': 'tool_call_requested'},
        {'event': 'tool_result', 'tool_used': true, 'retrieved_passage_count': 0, 'tool_error': false},
        {'event': 'completed', 'tool_used': true, 'retrieved_passage_count': 0, 'tool_error': false},
      ]);
      final e = finishRequest(run)!;
      expect(meta(e).containsKey('retrieved_passage_count'), true);
      expect(meta(e)['retrieved_passage_count'], 0);
      expect(meta(e)['tool_used'], true);
      expect(TelemetryContract.validate(e), isEmpty);
    });

    test('T4  Android sends no count at all but a tool was requested -> still 0, never missing', () {
      final run = play([
        {'event': 'tool_call_requested'},
        {'event': 'completed'},
      ]);
      expect(run.responseMetadata()['retrieved_passage_count'], 0);
    });

    test('T5  no tool used -> tool_used false and no passage count', () {
      final run = play([
        {'event': 'started'},
        {'event': 'token', 'text': 'Hi'},
        {'event': 'completed', 'tool_used': false, 'retrieved_passage_count': 0, 'tool_error': false},
      ]);
      final e = finishRequest(run)!;
      expect(meta(e)['tool_used'], false);
      expect(meta(e).containsKey('retrieved_passage_count'), false);
      expect(TelemetryContract.validate(e), isEmpty);
    });
  });

  group('RULE 3: tool execution fails', () {
    test('T6  Android reports TOOL_ERROR -> error / TOOL_ERROR / tool_execution / tool_used true', () {
      const message = 'tool call could not be executed: oncall_rag requires a local RAG store';
      final run = play([
        {'event': 'started'},
        {'event': 'tool_call_requested'},
        {
          'event': 'error',
          'error': message,
          'error_code': 'TOOL_ERROR',
          'error_stage': 'tool_execution',
          'tool_used': true,
          'retrieved_passage_count': 0,
          'tool_error': true,
        },
      ]);
      final e = finishRequest(run, thrown: Exception(message))!;
      expect(e.outcome, 'error');
      expect(e.errorCode, 'TOOL_ERROR');
      expect(meta(e)['error_stage'], 'tool_execution');
      expect(meta(e)['tool_used'], true);
      expect(meta(e)['retrieved_passage_count'], 0);
      expect(TelemetryContract.validate(e), isEmpty);
    });

    test('T7  tool failed but the model still answered -> STILL error / TOOL_ERROR / tool_used true', () {
      final run = play([
        {'event': 'tool_call_requested'},
        {'event': 'tool_result', 'tool_used': true, 'retrieved_passage_count': 0, 'tool_error': true},
        {'event': 'token', 'text': 'Sorry, I could not look that up.'},
        {'event': 'completed', 'tool_used': true, 'retrieved_passage_count': 0, 'tool_error': true},
      ]);
      final e = finishRequest(run)!; // no exception was thrown on the Dart side
      expect(e.outcome, 'error');
      expect(e.errorCode, 'TOOL_ERROR');
      expect(meta(e)['error_stage'], 'tool_execution');
      expect(meta(e)['tool_used'], true);
      expect(TelemetryContract.validate(e), isEmpty);
    });

    test('T8  user taps Stop while the tool is running -> cancelled, tool_used still true', () {
      final run = play([
        {'event': 'tool_call_requested'}, // stage becomes tool_execution
      ]);
      final e = finishRequest(run, cancelled: true)!;
      expect(e.outcome, 'cancelled');
      expect(e.errorCode, 'CANCELLED');
      expect(meta(e)['error_stage'], 'tool_execution');
      expect(meta(e)['tool_used'], true);
      expect(TelemetryContract.validate(e), isEmpty);
    });
  });

  group('RULE 4: the bug you reported (setup problem is NOT a tool error)', () {
    test('T9  new Android message: contract file missing -> NOT TOOL_ERROR', () {
      const message = 'Offline setup problem (no tool was run): the tool contract could not be loaded. '
          'asset not found. Tried: [tool_contract.json, contracts/tool_contract.json]';
      final run = play([
        {'event': 'started'},
        {'event': 'error', 'error': message, 'tool_used': false, 'retrieved_passage_count': 0, 'tool_error': false},
      ]);
      final failure = ChatRepositoryImpl.classifyOfflineError(Exception(message), run);
      expect(run.toolUsed, false);
      expect(failure.inferenceCode, isNull, reason: 'must not become an offline_inference TOOL_ERROR');
      expect(failure.runtimeCode, 'GENERATION_FAILED');
    });

    test('T10 OLD Android message "Unable to load shared tool contract" -> NOT TOOL_ERROR either', () {
      final run = play([
        {'event': 'started'},
        {'event': 'error', 'error': 'Unable to load shared tool contract'},
      ]);
      final failure =
          ChatRepositoryImpl.classifyOfflineError(Exception('Unable to load shared tool contract'), run);
      expect(failure.inferenceCode, isNull);
      expect(failure.runtimeCode, 'GENERATION_FAILED');
    });
  });

  group('The validator refuses contradictions (last line of defence)', () {
    test('T11 your exact bad diagnostics: TOOL_ERROR + tool_execution + tool_used false -> rejected', () {
      final bad = LocalTelemetryEvent(
        eventUuid: 'event-bad',
        eventType: TelemetryContract.offlineInference,
        chatId: 'chat-1',
        date: DateTime.now().toUtc().toIso8601String(),
        modelVersion: TelemetryContract.modelVersion,
        latencyMs: 900,
        outcome: 'error',
        errorCode: 'TOOL_ERROR',
        connectivity: 'offline',
        metadataJson: jsonEncode({'error_stage': 'tool_execution', 'tool_used': false}),
        syncState: 'pending',
      );
      final problems = TelemetryContract.validate(bad);
      expect(problems.any((p) => p.contains('tool_used must be true')), true, reason: '$problems');
    });

    test('T12 missing tool_used -> rejected', () {
      final bad = LocalTelemetryEvent(
        eventUuid: 'event-bad2',
        eventType: TelemetryContract.offlineInference,
        chatId: 'chat-1',
        date: DateTime.now().toUtc().toIso8601String(),
        modelVersion: TelemetryContract.modelVersion,
        latencyMs: 900,
        outcome: 'success',
        connectivity: 'offline',
        metadataJson: jsonEncode({'streamed': true}),
        syncState: 'pending',
      );
      expect(TelemetryContract.validate(bad), isNotEmpty);
    });

    test('T13 negative passage count -> rejected; 0 -> accepted', () {
      LocalTelemetryEvent withCount(int n) => LocalTelemetryEvent(
            eventUuid: 'event-count',
            eventType: TelemetryContract.offlineInference,
            chatId: 'chat-1',
            date: DateTime.now().toUtc().toIso8601String(),
            modelVersion: TelemetryContract.modelVersion,
            latencyMs: 900,
            outcome: 'success',
            connectivity: 'offline',
            metadataJson: jsonEncode({'tool_used': true, 'retrieved_passage_count': n}),
            syncState: 'pending',
          );
      expect(TelemetryContract.validate(withCount(-1)), isNotEmpty);
      expect(TelemetryContract.validate(withCount(0)), isEmpty);
    });
  });
}