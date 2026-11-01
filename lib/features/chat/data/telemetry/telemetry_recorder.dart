// NEW FILE  ->  lib/features/chat/data/telemetry/telemetry_recorder.dart
//
// WHY THIS FILE EXISTS (read this first, beginner friendly)
// ---------------------------------------------------------
// Before, telemetry events were built "by hand" in several places, with
// free-text values like 'online_inference' or 'offline_mode'. The backend only
// accepts the exact words written in the contract, so it refused your events.
//
// Now there is ONE place that creates telemetry:
//   1. TelemetryContract : every allowed word from the contract, written once.
//                          It can also CHECK an event before it is stored.
//   2. TelemetryRecorder : one method per event type (offline_started,
//                          offline_inference, offline_feedback,
//                          runtime_failure, sync_error).
//
// Rule: if an event does not follow the contract, it is NOT stored
// (a stored bad event would block every good event behind it, see notes).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../local/chat_local_data_source.dart';
import '../local/entities/local_telemetry_entity.dart';

// =============================================================================
// 1) THE CONTRACT, WRITTEN AS CODE
// =============================================================================
class TelemetryContract {
  TelemetryContract._();

  /// The local model's version label, exactly as in the contract examples.
  static const modelVersion = 'gemma-4-e2b-mobile';

  // The ONLY five event types. Nothing else (e.g. 'online_inference') is allowed.
  static const offlineStarted = 'offline_started';
  static const offlineInference = 'offline_inference';
  static const offlineFeedback = 'offline_feedback';
  static const runtimeFailure = 'runtime_failure';
  static const syncError = 'sync_error';

  static const eventTypes = <String>{
    offlineStarted,
    offlineInference,
    offlineFeedback,
    runtimeFailure,
    syncError,
  };

  static const connectivityValues = <String>{'offline', 'online', 'intermittent', 'unknown'};

  // offline_started
  static const previousConnectivityValues = <String>{'online', 'intermittent', 'unknown'};
  static const networkTypes = <String>{'wifi', 'cellular', 'none', 'unknown'};

  // offline_inference
  static const outcomes = <String>{'success', 'error', 'cancelled'};
  static const inferenceErrorCodes = <String>{
    'MODEL_UNAVAILABLE',
    'GENERATION_TIMEOUT',
    'CONTEXT_LIMIT',
    'TOOL_ERROR',
    'CANCELLED',
  };
  static const inferenceErrorStages = <String>{
    'model_load',
    'retrieval',
    'context_build',
    'generation',
    'tool_execution',
  };

  // offline_feedback
  static const feedbackValues = <String>{'positive', 'negative', 'not_helpful'};

  // runtime_failure
  static const runtimeErrorCodes = <String>{
    'APP_CRASH',
    'OUT_OF_MEMORY',
    'MODEL_LOAD_FAILED',
    'GENERATION_FAILED',
  };
  static const failureTypes = <String>{
    'crash',
    'out_of_memory',
    'model_load_failure',
    'generation_failure',
  };
  static const failureStages = <String>{
    'app_startup',
    'model_load',
    'retrieval',
    'generation',
    'tool_execution',
  };

  // sync_error
  static const syncTargets = <String>{'chat', 'telemetry'};
  static const syncErrorCodes = <String>{
    'NETWORK_UNAVAILABLE',
    'SYNC_TIMEOUT',
    'UNAUTHORIZED',
    'SERVER_ERROR',
    'INVALID_PAYLOAD',
  };

  /// The contract says metadata must NEVER hold these (full messages, secrets...).
  static const _forbiddenMetadataKeys = <String>{
    'message',
    'ai_response',
    'prompt',
    'response',
    'full_response',
    'access_token',
    'token',
    'password',
    'stack',
    'stack_trace',
    'stacktrace',
  };

  /// Checks one event against the contract.
  /// Returns a list of problems. EMPTY LIST = the backend will accept it.
  static List<String> validate(LocalTelemetryEvent e) {
    final problems = <String>[];
    void need(bool ok, String message) {
      if (!ok) problems.add(message);
    }

    if (!eventTypes.contains(e.eventType)) {
      return ['event_type "${e.eventType}" is not one of the five allowed event types'];
    }
    need(connectivityValues.contains(e.connectivity), 'connectivity "${e.connectivity}" is not allowed');

    final parsedDate = DateTime.tryParse(e.date);
    need(parsedDate != null && parsedDate.isUtc, 'date must be an ISO-8601 UTC time ending in Z');

    // metadata must be a JSON object
    Map<String, dynamic> meta = {};
    try {
      final decoded = jsonDecode(e.metadataJson);
      if (decoded is Map<String, dynamic>) {
        meta = decoded;
      } else {
        problems.add('metadata must be a JSON object');
      }
    } catch (_) {
      problems.add('metadata is not valid JSON');
    }
    for (final key in meta.keys) {
      need(!_forbiddenMetadataKeys.contains(key.toLowerCase()),
          'metadata must not contain "$key" (no messages, tokens or stack traces)');
    }

    switch (e.eventType) {
      case offlineStarted:
        need(e.connectivity == 'offline', 'offline_started: connectivity must be "offline"');
        need(e.latencyMs == null, 'offline_started: latency_ms must be null');
        need(e.outcome == null, 'offline_started: outcome must be null');
        need(e.errorCode == null, 'offline_started: error_code must be null');
        need(previousConnectivityValues.contains(meta['previous_connectivity']),
            'offline_started: metadata.previous_connectivity is required (online/intermittent/unknown)');
        need(networkTypes.contains(meta['network_type']),
            'offline_started: metadata.network_type is required (wifi/cellular/none/unknown)');
        break;

      case offlineInference:
        need(e.chatId != null && e.chatId!.isNotEmpty, 'offline_inference: chat_id is required');
        need(e.modelVersion != null, 'offline_inference: model_version is required');
        need(e.latencyMs != null && e.latencyMs! >= 0, 'offline_inference: latency_ms is required');
        need(e.connectivity == 'offline', 'offline_inference: connectivity must be "offline"');
        need(outcomes.contains(e.outcome), 'offline_inference: outcome must be success/error/cancelled');
        if (e.outcome == 'success') {
          need(e.errorCode == null, 'offline_inference: error_code must be null on success');
        } else {
          need(inferenceErrorCodes.contains(e.errorCode),
              'offline_inference: error_code "${e.errorCode}" is not allowed');
          need(inferenceErrorStages.contains(meta['error_stage']),
              'offline_inference: metadata.error_stage is required when outcome is not success');
        }
        if (e.outcome == 'cancelled') {
          need(e.errorCode == 'CANCELLED', 'offline_inference: cancelled needs error_code CANCELLED');
        }
        if (meta['output_tokens'] != null) {
          need(meta['output_tokens'] is int && (meta['output_tokens'] as int) >= 0,
              'offline_inference: output_tokens must be a whole number');
        }
        break;

      case offlineFeedback:
        need(e.chatId != null && e.chatId!.isNotEmpty, 'offline_feedback: chat_id is required');
        need(e.connectivity == 'offline', 'offline_feedback: connectivity must be "offline"');
        need(e.latencyMs == null, 'offline_feedback: latency_ms must be null');
        need(e.outcome == null, 'offline_feedback: outcome must be null');
        need(e.errorCode == null, 'offline_feedback: error_code must be null');
        need(feedbackValues.contains(meta['feedback_value']),
            'offline_feedback: metadata.feedback_value must be positive/negative/not_helpful');
        break;

      case runtimeFailure:
        need(e.outcome == null, 'runtime_failure: outcome must be null');
        need(runtimeErrorCodes.contains(e.errorCode),
            'runtime_failure: error_code "${e.errorCode}" is not allowed');
        need(failureTypes.contains(meta['failure_type']), 'runtime_failure: metadata.failure_type is required');
        need(failureStages.contains(meta['failure_stage']), 'runtime_failure: metadata.failure_stage is required');
        break;

      case syncError:
        need(e.outcome == null, 'sync_error: outcome must be null');
        need(syncErrorCodes.contains(e.errorCode), 'sync_error: error_code "${e.errorCode}" is not allowed');
        need(syncTargets.contains(meta['sync_target']), 'sync_error: metadata.sync_target must be chat/telemetry');
        break;
    }
    return problems;
  }
}

// =============================================================================
// 2) THE RECORDER: one method per event type
// =============================================================================
class TelemetryRecorder {
  TelemetryRecorder(this._local);

  final ChatLocalDataSource _local;
  static const _uuid = Uuid();

  /// sync_error is throttled so a phone that keeps failing to sync does not
  /// fill the database with hundreds of identical events.
  static const _syncErrorCooldown = Duration(minutes: 5);
  final Map<String, DateTime> _lastSyncErrorAt = {};

  // ---------------------------------------------------------------------------
  // The one place where an event is built and stored
  // ---------------------------------------------------------------------------
  Future<void> _save({
    required String eventType,
    String? chatId,
    String? modelVersion,
    int? latencyMs,
    String? outcome,
    String? errorCode,
    required String connectivity,
    required Map<String, Object?> metadata,
  }) async {
    try {
      final event = LocalTelemetryEvent(
        // Created ONCE here. Retries during sync re-send this same value.
        eventUuid: 'event-${_uuid.v4()}',
        eventType: eventType,
        chatId: chatId,
        date: DateTime.now().toUtc().toIso8601String(),
        modelVersion: modelVersion,
        latencyMs: latencyMs,
        outcome: outcome,
        errorCode: errorCode,
        connectivity: connectivity,
        // jsonEncode builds valid JSON for us. Never glue JSON text together by hand.
        metadataJson: jsonEncode(metadata),
        syncState: 'pending',
      );

      final problems = TelemetryContract.validate(event);
      if (problems.isNotEmpty) {
        // Storing it would make the backend reject the whole upload.
        debugPrint('TELEMETRY NOT SAVED (breaks the contract): $problems');
        return;
      }
      await _local.saveTelemetryEvent(event);
    } catch (e) {
      // Telemetry must NEVER crash the chat.
      debugPrint('TELEMETRY SAVE FAILED: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // offline_started : once, when the phone goes from "has network" to "none"
  // ---------------------------------------------------------------------------
  Future<void> recordOfflineStarted({
    String? chatId,
    String? modelVersion,
    required String previousConnectivity, // online | intermittent | unknown
    required String networkType, // wifi | cellular | none | unknown
  }) {
    return _save(
      eventType: TelemetryContract.offlineStarted,
      chatId: chatId,
      modelVersion: modelVersion,
      connectivity: 'offline', // fixed by the contract
      metadata: {
        'previous_connectivity': previousConnectivity,
        'network_type': networkType,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // offline_inference : once per local AI request (success, error OR cancelled)
  // ---------------------------------------------------------------------------
  Future<void> recordOfflineInference({
    required String chatId,
    required String modelVersion,
    required int latencyMs,
    required String outcome, // success | error | cancelled
    String? errorCode, // null when success
    String? errorStage, // null when success
    Map<String, Object?> responseMetadata = const {},
  }) {
    return _save(
      eventType: TelemetryContract.offlineInference,
      chatId: chatId,
      modelVersion: modelVersion,
      latencyMs: latencyMs,
      outcome: outcome,
      errorCode: errorCode,
      connectivity: 'offline', // fixed by the contract
      metadata: {
        'error_stage': errorStage,
        ...responseMetadata, // output_tokens, tool_used, streamed, ...
      },
    );
  }

  // ---------------------------------------------------------------------------
  // offline_feedback : the user rated an offline answer
  // ---------------------------------------------------------------------------
  Future<void> recordOfflineFeedback({
    required String chatId,
    String? modelVersion,
    required String feedbackValue, // positive | negative | not_helpful
    String? comment,
  }) {
    final trimmed = comment?.trim();
    return _save(
      eventType: TelemetryContract.offlineFeedback,
      chatId: chatId,
      modelVersion: modelVersion,
      connectivity: 'offline',
      metadata: {
        'feedback_value': feedbackValue,
        if (trimmed != null && trimmed.isNotEmpty)
          'feedback_comment': trimmed.length > 280 ? trimmed.substring(0, 280) : trimmed,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // runtime_failure : crash / out of memory / failures with no normal inference
  // ---------------------------------------------------------------------------
  Future<void> recordRuntimeFailure({
    String? chatId,
    String? modelVersion,
    int? latencyMs,
    required String errorCode, // APP_CRASH | OUT_OF_MEMORY | MODEL_LOAD_FAILED | GENERATION_FAILED
    required String failureType, // crash | out_of_memory | model_load_failure | generation_failure
    required String failureStage, // app_startup | model_load | retrieval | generation | tool_execution
    String connectivity = 'unknown',
  }) {
    return _save(
      eventType: TelemetryContract.runtimeFailure,
      chatId: chatId,
      modelVersion: modelVersion,
      latencyMs: latencyMs,
      errorCode: errorCode,
      connectivity: connectivity,
      metadata: {
        'failure_type': failureType,
        'failure_stage': failureStage,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // sync_error : a chat upload or a telemetry upload failed
  // ---------------------------------------------------------------------------
  Future<void> recordSyncError({
    String? chatId, // null for a telemetry-only failure
    int? latencyMs,
    required String errorCode, // NETWORK_UNAVAILABLE | SYNC_TIMEOUT | UNAUTHORIZED | SERVER_ERROR | INVALID_PAYLOAD
    required String connectivity,
    required String syncTarget, // chat | telemetry
    int? pendingChatCount,
    int? pendingEventCount,
    int? httpStatus, // null when no response arrived
  }) {
    final key = '$syncTarget|$errorCode';
    final last = _lastSyncErrorAt[key];
    if (last != null && DateTime.now().difference(last) < _syncErrorCooldown) {
      return Future.value(); // same failure was just recorded
    }
    _lastSyncErrorAt[key] = DateTime.now();

    return _save(
      eventType: TelemetryContract.syncError,
      chatId: chatId,
      latencyMs: latencyMs,
      errorCode: errorCode,
      connectivity: connectivity,
      metadata: {
        'sync_target': syncTarget,
        // ignore: use_null_aware_elements
        if (pendingChatCount != null) 'pending_chat_count': pendingChatCount,
        // ignore: use_null_aware_elements
        if (pendingEventCount != null) 'pending_event_count': pendingEventCount,
        'http_status': httpStatus,
      },
    );
  }

  // ===========================================================================
  // CRASH / OUT-OF-MEMORY DETECTION  (the contract's "durable failure marker")
  // ===========================================================================
  // A crashed app cannot write its own telemetry: it is already dead.
  // So we do this instead:
  //   * when an on-phone answer STARTS  -> write a tiny file "I am working"
  //   * when it ENDS normally           -> delete that file
  //   * next time the app opens         -> if the file is still there, the app
  //     died in the middle (crash or Android killed it) -> record runtime_failure.
  Map<String, Object?>? _activeMarker;

  Future<File> _markerFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'inference_in_progress.json'));
  }

  Future<void> beginInferenceMarker({
    required String chatId,
    required String modelVersion,
    required String connectivity,
    required String stage, // model_load | generation
  }) async {
    _activeMarker = {
      'chat_id': chatId,
      'model_version': modelVersion,
      'connectivity': connectivity,
      'stage': stage,
    };
    await _writeMarker();
  }

  Future<void> updateInferenceMarkerStage(String stage) async {
    final marker = _activeMarker;
    if (marker == null) return;
    marker['stage'] = stage;
    await _writeMarker();
  }

  Future<void> _writeMarker() async {
    try {
      final file = await _markerFile();
      await file.writeAsString(jsonEncode(_activeMarker), flush: true);
    } catch (_) {}
  }

  Future<void> endInferenceMarker() async {
    _activeMarker = null;
    try {
      final file = await _markerFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Call ONCE at app start (main.dart), before syncing starts.
  Future<void> recoverFromPreviousRun() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return;

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      await file.delete();

      final stage = data['stage'] == 'model_load' ? 'model_load' : 'generation';
      final connectivity = data['connectivity'];
      await recordRuntimeFailure(
        chatId: data['chat_id'] as String?,
        modelVersion: data['model_version'] as String?,
        // We cannot tell a crash from "Android killed us for memory", so we
        // use the general, honest classification.
        errorCode: 'APP_CRASH',
        failureType: 'crash',
        failureStage: stage,
        connectivity:
            TelemetryContract.connectivityValues.contains(connectivity) ? connectivity as String : 'unknown',
      );
    } catch (_) {}
  }
}