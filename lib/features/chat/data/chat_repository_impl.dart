import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // debugPrint, kDebugMode

import 'ai/native_offline_ai_service.dart';
import 'ai/chat_context.dart';
import 'ai/model_setup_service.dart';
import '../domain/chat_repository.dart';
import '../domain/chat_session.dart';
import '../domain/chat_turn.dart';
import '../../../core/network/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/security/token_storage.dart';
import 'local/chat_local_data_source.dart';
import 'local/diagnostic_logger.dart';
import 'local/entities/local_chat_entity.dart';
import 'telemetry/device_telemetry.dart';
import 'telemetry/telemetry_recorder.dart';

import 'package:uuid/uuid.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required this.apiClient,
    required this.localDataSource,
    required this.tokenStorage,
    required this.nativeAiService,
    required this.diagnosticLogger,
    required this.modelSetupService,
    required this.telemetry,
  });

  final ApiClient apiClient;
  final ChatLocalDataSource localDataSource;
  final TokenStorage tokenStorage;
  final NativeOfflineAiService nativeAiService;
  final DiagnosticLogger diagnosticLogger;
  final ModelSetupService modelSetupService;
  final TelemetryRecorder telemetry;

  static const _recordCloudFallbackAsOffline = true;

  // ---- The "stop switches" for the answer that is being written right now ----
  // _stop         : flipped when the person taps Stop (works for cloud AND offline)
  // _cloudCancel  : lets us hang up the internet request immediately
  Completer<void>? _stop;
  CancelToken? _cloudCancel;

  @override
  Future<List<ChatTurn>> loadHistory() async {
    final chatId = await tokenStorage.activeChatId();
    final localMessages = await localDataSource.getMessages(chatId);

    return localMessages
        .map(
          (msg) => ChatTurn(
            id: msg.id.toString(),
            message: msg.message,
            aiResponse: msg.aiResponse,
            date: msg.date,
            state: msg.source == 'offline' ? 'offline' : 'online',
            synced: msg.syncState == 'acknowledged',
            isError: msg.syncState == ChatLocalDataSource.stateInterrupted,
          ),
        )
        .toList();
  }

  @override
  Future<List<ChatSession>> loadChatSessions() async {
    final chats = await localDataSource.getChats();
    final sessions = <ChatSession>[];

    for (final chat in chats) {
      final count = await localDataSource.countMessages(chat.chatId);
      if (count == 0) continue; // a chat with no messages is not worth showing

      final first = await localDataSource.getFirstMessage(chat.chatId);
      sessions.add(
        ChatSession(
          id: chat.chatId,
          title: _shortTitle(first?.message),
          updatedAt: chat.updatedAt,
          messageCount: count,
        ),
      );
    }
    return sessions;
  }

  @override
  Future<String> activeChatId() => tokenStorage.activeChatId();

  @override
  Future<void> openChat(String chatId) => tokenStorage.setActiveChat(chatId);

  @override
  Future<void> deleteChat(String chatId) async {
    await localDataSource.deleteChat(chatId);

    // If the deleted chat was the open one, move to a fresh blank chat.
    final active = await tokenStorage.activeChatId();
    if (active == chatId) {
      await tokenStorage.startNewChat();
    }
  }

  /// One-line title for the history drawer.
  static String _shortTitle(String? text) {
    final clean = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'New chat';
    if (clean.length <= 48) return clean;
    return '${clean.substring(0, 48).trimRight()}…';
  }

  @override
  Stream<ChatTurn> sendMessage(String text, {required bool isOnline}) async* {
    final chatId = await tokenStorage.activeChatId();
    final userId = await tokenStorage.localUserId();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final turnId = 'turn-${const Uuid().v4()}';

    // Read the conversation BEFORE saving this new question, so the list is
    // exactly the earlier turns. The local database is the one place where the
    // complete conversation lives: online turns are saved here too. Passing it
    // to the on-phone model lets offline answers remember what was discussed
    // online (and the other way round).
    //
    // The cloud is NOT given this transcript. The backend now stores online and
    // offline turns under the same chat id, so its own history is complete.
    var earlierRows = const <LocalChatMessage>[];
    try {
      earlierRows = await localDataSource.getMessages(chatId);
    } catch (e) {
      debugPrint('Could not load conversation context: $e'); // chat still works
    }
    final offlineHistory = ChatContext.offlineMessages(earlierRows);

    // Fresh stop switches for THIS answer.
    final stop = Completer<void>();
    final cancelToken = CancelToken();
    _stop = stop;
    _cloudCancel = cancelToken;

    // 1. Show the "thinking" bubble straight away.
    var currentTurn = ChatTurn(
      id: turnId,
      message: text,
      aiResponse: '',
      date: timestamp,
      state: isOnline ? 'online' : 'offline',
      isStreaming: true,
    );
    yield currentTurn;

    // SAVE THE QUESTION NOW (not at the end). Offline answers can take minutes;
    // if the app is closed meanwhile, the question and the words written so far
    // must still be there when the person comes back.
    int? rowId;
    try {
      rowId = await localDataSource.beginTurn(
        chatId: chatId,
        message: text,
        date: timestamp,
        source: isOnline ? 'cloud' : 'offline',
      );
    } catch (e) {
      debugPrint('Could not save the question early: $e'); // chat still works
    }
    final saveClock = Stopwatch()..start(); // throttles the progress saves

    var aiResponse = '';
    var success = true;
    var stopped = false; // did the person tap Stop?
    var usedOffline = !isOnline;
    Object? cloudError; // remembered so we can explain it if offline also fails
    var needOffline = !isOnline;
    final overall = Stopwatch()
      ..start(); // only for the separate diagnostic log

    // TELEMETRY bookkeeping (only used when the on-phone model is involved)
    final run = OfflineRun(
      // Samples memory/thermal/battery while this answer runs.
      envelope: DeviceEnvelopeSampler(telemetry.deviceTelemetry),
    ); // collects real measurements from the phone model
    var offlineAttempted = false; // was the on-phone model asked at all?
    var reachedTheEnd = false; // false = the screen closed in the middle
    OfflineFailure? failure; // why the on-phone model failed (if it did)

    try {
      // -----------------------------------------------------------------------
      // STEP A: try the cloud (only when the phone says it is online)
      // An answer from the cloud creates NO telemetry: the contract has no
      // event for it.
      // -----------------------------------------------------------------------
      if (isOnline) {
        try {
          aiResponse = await _askCloud(text, chatId, cancelToken);
          currentTurn = currentTurn.copyWith(
            aiResponse: aiResponse,
            state: 'online',
          );
          yield currentTurn;
        } catch (e) {
          if (stop.isCompleted) {
            // The person tapped Stop. This is NOT a failure: do not fall back.
            stopped = true;
          } else {
            cloudError = e;
            debugPrint('CLOUD CHAT ERROR: ${_explainError(e)}');
            if (await modelSetupService.existingPath() != null) {
              needOffline = true; // cloud failed, the phone model can help
            } else {
              success = false;
              aiResponse = _friendlyCloudMessage(e);
              // Only while you test: also show the real technical reason.
              if (kDebugMode) aiResponse += '\n\n[debug] ${_explainError(e)}';
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // STEP B: the model on the phone (offline, or as a backup for the cloud)
      // -----------------------------------------------------------------------
      if (needOffline && !stopped) {
        usedOffline = true;
        offlineAttempted = true;
        aiResponse = '';
        try {
          await for (final event in _offlineEvents(
            userId,
            chatId,
            text,
            stop,
            run,
            isOnline: isOnline,
            history: offlineHistory,
          )) {
            if (event.type == AiEventType.token) {
              aiResponse += event.text;
              // Save progress at most every 1.5 s (a database write per word would be wasteful).
              if (rowId != null && saveClock.elapsedMilliseconds >= 1500) {
                saveClock.reset();
                try {
                  await localDataSource.updateTurn(
                    rowId,
                    aiResponse: aiResponse,
                    source: 'offline',
                  );
                } catch (_) {}
              }
              currentTurn = currentTurn.copyWith(
                aiResponse: aiResponse,
                state: 'offline',
              );
              yield currentTurn;
            } else if (event.type == AiEventType.completed) {
              if (aiResponse.isEmpty && event.text.isNotEmpty) {
                aiResponse = event.text;
              }
              currentTurn = currentTurn.copyWith(
                aiResponse: aiResponse,
                state: 'offline',
              );
              yield currentTurn;
            } else if (event.type == AiEventType.error) {
              throw Exception(event.error);
            }
            // 'cancelled' and other events need no action here
            // (run.observe() inside _offlineEvents already noted them).
          }
          if (stop.isCompleted) stopped = true;
        } catch (e) {
          if (stop.isCompleted) {
            stopped = true;
          } else {
            success = false;
            failure = classifyOfflineError(e, run); // TELEMETRY: contract words
            if (cloudError != null) {
              aiResponse =
                  '${_friendlyCloudMessage(cloudError)}\n\n'
                  'The offline assistant also failed: $e';
            } else if (e.toString().contains('offline_model_missing')) {
              aiResponse =
                  'You are offline, and the optional offline assistant is not '
                  'downloaded. Please download it from the banner above.';
            } else {
              aiResponse = 'The offline assistant encountered an error: $e';
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // STEP C: the person tapped Stop
      // -----------------------------------------------------------------------
      if (stopped) {
        if (aiResponse.trim().isEmpty) {
          // Stopped before a single word arrived: nothing worth saving.
          success = false;
          aiResponse = 'Answer stopped.';
        }
        // Otherwise we KEEP the part that was already written and save it.
      }

      reachedTheEnd = true;
      overall.stop();

      if (rowId != null) {
        if (success && aiResponse.trim().isNotEmpty) {
          await localDataSource.finishTurn(
            rowId,
            aiResponse: aiResponse,
            source: usedOffline ? 'offline' : 'cloud',
          );
        } else {
          // Failed or stopped with nothing written: same as before, not kept.
          await localDataSource.deleteTurn(rowId);
        }
        rowId = null; // handled: the `finally` below must not touch it again
      }
    } finally {
      // The screen was closed (or the stream cancelled) BEFORE the normal ending.
      // Keep whatever was written so far, and stop the phone model, otherwise it
      // keeps working in the background and blocks the next question.
      if (!reachedTheEnd) {
        final leftover = rowId;
        if (leftover != null) {
          try {
            await localDataSource.interruptTurn(
              leftover,
              partial: aiResponse,
              source: usedOffline ? 'offline' : 'cloud',
            );
          } catch (_) {}
        }
        if (offlineAttempted) {
          await nativeAiService.cancelGeneration(chatId);
        }
      }

      // `finally` ALWAYS runs: after success, after an error, and even if the
      // screen is closed in the middle of the answer.
      run.clock.stop();
      if (identical(_stop, stop)) _stop = null;
      if (identical(_cloudCancel, cancelToken)) _cloudCancel = null;

      await telemetry.endInferenceMarker(); // we finished: no crash happened

      // TELEMETRY: exactly ONE event for this on-phone request.
      if (offlineAttempted && (!isOnline || _recordCloudFallbackAsOffline)) {
        try {
          await _recordOfflineTelemetry(
            chatId: chatId,
            isOnline: isOnline,
            run: run,
            cancelled: stopped || run.nativeCancelled || !reachedTheEnd,
            failure: failure,
          );
        } catch (e) {
          // A telemetry problem must never suppress the diagnostic log or the
          // final answer shown to the user.
          debugPrint('TELEMETRY RECORD FAILED: $e');
          diagnosticLogger.logEvent(
            logType: 'telemetry_event_failed',
            metrics: {
              'event_type': 'offline_inference',
              'chat_id': chatId,
              'error': e.toString().length > 500
                  ? e.toString().substring(0, 500)
                  : e.toString(),
            },
          );
        }
      }
    }

    // Separate local diagnostic log (not part of the telemetry contract).
    // It now carries the SAME device/runtime envelope as telemetry:
    //   * device: model, total RAM, RAM class, CPU/ABI, backend
    //   * memory: available at start, process PSS at start, PEAK process PSS
    //   * thermal: status/headroom at start and end
    //   * battery: percent, temperature, charging
    //   * model_load_ms: how long the 2.5 GB model took to load
    // The measured values come from the sampler that was running during the
    // answer. For a cloud-only answer there is no sampler data, so the logger
    // fills in a live snapshot instead.
    final runtimeDiagnostics = offlineAttempted
        ? await run.envelope.metadata()
        : const <String, Object?>{};
    diagnosticLogger.logEvent(
      logType: 'inference_measurement',
      metrics: {
        'latency_ms': overall.elapsedMilliseconds,
        'success': success,
        // The same RAG facts that go into telemetry. Diagnostics is the
        // channel that currently always reaches the backend, so keeping these
        // here means an offline answer is still analysable even if
        // /v1/telemetry rejects or delays the event.
        'tool_used': run.toolUsed,
        'retrieved_passage_count': run.retrievedPassageCount ?? 0,
        'streamed': run.streamed,
        if (run.modelLoadMs != null) 'model_load_ms': run.modelLoadMs,
        if (run.nativeOutputTokens != null)
          'output_tokens': run.nativeOutputTokens,
        if (run.firstTokenMs != null)
          'time_to_first_token_ms': run.firstTokenMs,
        ...runtimeDiagnostics,
      },
    );

    // 5. Final turn for the screen.
    yield currentTurn.copyWith(
      aiResponse: aiResponse,
      state: usedOffline ? 'offline' : 'online',
      isStreaming: false,
      isError: !success && !stopped, // "Answer stopped." is not an error
      synced: false,
    );
  }

  // ---------------------------------------------------------------------------
  // TELEMETRY: turn what happened into ONE contract-shaped event.
  // ---------------------------------------------------------------------------
  Future<void> _recordOfflineTelemetry({
    required String chatId,
    required bool isOnline,
    required OfflineRun run,
    required bool cancelled,
    required OfflineFailure? failure,
  }) async {
    final latencyMs = run.clock.elapsedMilliseconds; // on-phone time only
    // Stops the sampler, then returns measurements + device envelope.
    // If the envelope itself ever fails, still send the core measurements:
    // losing a device block is much better than losing the whole event.
    Map<String, Object?> responseMetadata;
    try {
      responseMetadata = await run.fullResponseMetadata();
    } catch (e) {
      debugPrint('TELEMETRY ENVELOPE BUILD FAILED: $e');
      responseMetadata = run.responseMetadata();
    }

    // A tool FAILED while it was running, even though the model still wrote an
    // answer. The contract still wants: outcome "error", TOOL_ERROR, tool_execution
    // (and tool_used stays true, because a tool call really happened).
    failure = finalFailure(cancelled: cancelled, failure: failure, run: run);
    const model = TelemetryContract.modelVersion;

    if (cancelled) {
      await telemetry.recordOfflineInference(
        chatId: chatId,
        modelVersion: model,
        latencyMs: latencyMs,
        outcome: 'cancelled',
        errorCode: 'CANCELLED',
        errorStage: run.stage,
        responseMetadata: responseMetadata,
      );
    } else if (failure == null) {
      await telemetry.recordOfflineInference(
        chatId: chatId,
        modelVersion: model,
        latencyMs: latencyMs,
        outcome: 'success',
        responseMetadata: responseMetadata,
      );
    } else if (failure.inferenceCode != null) {
      await telemetry.recordOfflineInference(
        chatId: chatId,
        modelVersion: model,
        latencyMs: latencyMs,
        outcome: 'error',
        errorCode: failure.inferenceCode,
        errorStage: failure.stage,
        responseMetadata: responseMetadata,
      );
    } else {
      // The error does not fit any of the five offline_inference codes.
      // The contract's answer for that is a runtime_failure.
      await telemetry.recordRuntimeFailure(
        chatId: chatId,
        modelVersion: model,
        latencyMs: latencyMs,
        errorCode: failure.runtimeCode!,
        failureType: failure.failureKind!,
        failureStage: failure.runtimeStage,
        connectivity: isOnline ? 'online' : 'offline',
        extraMetadata: responseMetadata,
      );
    }
  }

  /// Decides the final failure for telemetry. A tool failure is still reported
  /// as an error even when the model managed to finish an answer.
  @visibleForTesting
  static OfflineFailure? finalFailure({
    required bool cancelled,
    required OfflineFailure? failure,
    required OfflineRun run,
  }) {
    if (!cancelled && failure == null && run.toolFailed) {
      return OfflineFailure.inference('TOOL_ERROR', 'tool_execution');
    }
    return failure;
  }

  /// Turns an error into the contract's words.
  /// Order matters: the most specific checks come first.
  @visibleForTesting
  static OfflineFailure classifyOfflineError(Object error, OfflineRun run) {
    final text = error.toString().toLowerCase();

    // 1) Out of memory is its own runtime failure.
    if (text.contains('out of memory') ||
        text.contains('outofmemory') ||
        RegExp(r'\boom\b').hasMatch(text)) {
      return OfflineFailure.runtime(
        'OUT_OF_MEMORY',
        'out_of_memory',
        run.stage,
      );
    }
    // 2) If Android already sent a valid contract code, trust it.
    final nativeCode = run.nativeErrorCode;
    if (nativeCode != null &&
        TelemetryContract.inferenceErrorCodes.contains(nativeCode)) {
      final stage =
          TelemetryContract.inferenceErrorStages.contains(run.nativeErrorStage)
          ? run.nativeErrorStage!
          : run.stage;
      return OfflineFailure.inference(nativeCode, stage);
    }
    // 3) Failed while loading / model file missing.
    if (text.contains('offline_model_missing') || run.stage == 'model_load') {
      return OfflineFailure.inference('MODEL_UNAVAILABLE', 'model_load');
    }
    // 4) Took too long (Android's 120 s limit, or our 4 minute watchdog).
    if (text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('stopped responding')) {
      return OfflineFailure.inference('GENERATION_TIMEOUT', run.stage);
    }
    // 5) The question + knowledge did not fit in the model's memory window.
    if (text.contains('context') &&
        (text.contains('limit') ||
            text.contains('length') ||
            text.contains('window'))) {
      return OfflineFailure.inference('CONTEXT_LIMIT', 'context_build');
    }
    // 6) A tool failed. ONLY when a tool call really happened (tool_used = true).
    //    The old test `text.contains('tool')` also matched "Unable to load shared
    //    tool contract", a SETUP problem where no tool ever ran. That produced
    //    TOOL_ERROR + tool_used:false, which contradicts itself.
    if (run.toolUsed && (run.stage == 'tool_execution' || run.toolFailed)) {
      return OfflineFailure.inference('TOOL_ERROR', 'tool_execution');
    }
    // 7) Unknown generation failure.
    return OfflineFailure.runtime(
      'GENERATION_FAILED',
      'generation_failure',
      run.stage,
    );
  }

  // ---------------------------------------------------------------------------
  // Ask the cloud. Returns the answer text, or throws.
  // ---------------------------------------------------------------------------
  Future<String> _askCloud(
    String text,
    String chatId,
    CancelToken cancelToken,
  ) async {
    if (Env.apiKey.isEmpty) {
      throw Exception('missing_api_key');
    }

    // The cloud keeps the conversation on its side. The backend stores online
    // and offline turns under the same chat id, so nothing extra needs to be
    // injected into the question here.
    Future<Response<dynamic>> send() => apiClient.dio.post(
      '/user/chat',
      data: {'message': text},
      cancelToken: cancelToken, // <- this is what lets Stop hang up
      options: Options(
        headers: {'X-CHAT-ID': chatId},
        sendTimeout: const Duration(seconds: 20),
        // AI answers (especially the first one after a pause) can be slow.
        receiveTimeout: const Duration(seconds: 90),
      ),
    );

    Response<dynamic> response;
    try {
      response = await send();
    } on DioException catch (e) {
      // A shaky mobile network often fails once and works a second later.
      // We retry ONLY when the request never reached the server, so the
      // question can never be asked twice.
      final neverArrived =
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      if (!neverArrived) rethrow;
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await send();
    }

    debugPrint('CLOUD CHAT <- status ${response.statusCode}');

    final data = response.data;
    final answer = data is Map ? data['ai_response'] : null;
    if (answer is! String || answer.trim().isEmpty) {
      throw Exception('unexpected_reply_shape: $data');
    }
    return answer;
  }

  // ---------------------------------------------------------------------------
  // Talk to the on-phone model. Ends early (without error) if Stop is tapped,
  // even while the big model is still loading or Android is silent.
  // `run` quietly collects the real measurements used by telemetry.
  // ---------------------------------------------------------------------------
  Stream<AiEvent> _offlineEvents(
    String userId,
    String chatId,
    String text,
    Completer<void> stop,
    OfflineRun run, {
    required bool isOnline,
    List<Map<String, String>> history = const [],
  }) async* {
    await run.envelope.start(); // begin sampling memory/thermal/battery
    run.clock.start(); // latency = from here until the answer ends
    run.stage = 'model_load';

    final modelPath = await modelSetupService.existingPath();
    if (modelPath == null) {
      throw Exception('offline_model_missing');
    }

    // Crash marker: if the app dies from here on, the next start reports it.
    await telemetry.beginInferenceMarker(
      chatId: chatId,
      modelVersion: TelemetryContract.modelVersion,
      connectivity: isOnline ? 'online' : 'offline',
      stage: 'model_load',
    );

    final knowledgePath = await modelSetupService.prepareKnowledge();
    final runtimePath = await modelSetupService.runtimePath();

    // Loading the 2.5 GB model can take a while: Stop must work during it too.
    await Future.any<void>([
      nativeAiService.ensureInitialized(
        modelPath: modelPath,
        knowledgePath: knowledgePath,
        runtimePath: runtimePath,
      ),
      stop.future,
    ]);
    // The 2.5 GB model is now in memory: this is how long loading took.
    run.modelLoadMs = run.clock.elapsedMilliseconds;
    run.generationStartedMs = run.clock.elapsedMilliseconds;
    if (stop.isCompleted) return;

    run.stage = 'generation';
    await telemetry.updateInferenceMarkerStage('generation');

    final events = StreamIterator<AiEvent>(
      nativeAiService.generate(
        userId: userId,
        sessionId: chatId,
        chatId: chatId,
        message: text,
        history: history,
      ),
    );
    try {
      while (true) {
        // Wait for the next word OR for the Stop tap, whichever comes first.
        final hasNext = await Future.any<bool>([
          events.moveNext(),
          stop.future.then((_) => false),
        ]);
        if (!hasNext) break;
        run.observe(events.current); // TELEMETRY: note timing, tokens, tools
        yield events.current;
      }
    } finally {
      await events.cancel();
    }
  }

  /// TELEMETRY: the person rated an OFFLINE answer (offline_feedback).
  /// [feedbackValue] must be 'positive', 'negative' or 'not_helpful'.
  /// Only the rating (+ optional short comment) is stored: never the answer text.
  @override
  Future<void> submitFeedback({
    required String feedbackValue,
    String? comment,
  }) async {
    final chatId = await tokenStorage.activeChatId();
    await telemetry.recordOfflineFeedback(
      chatId: chatId,
      modelVersion: TelemetryContract.modelVersion,
      feedbackValue: feedbackValue,
      comment: comment,
    );
  }

  @override
  Future<void> startNewChat() async {
    final oldChatId = await tokenStorage.activeChatId();
    await nativeAiService.cancelGeneration(oldChatId);
    await tokenStorage.startNewChat();
  }

  /// The Stop button. Works for BOTH the cloud and the on-phone model.
  @override
  Future<void> cancelGeneration() async {
    final stop = _stop;
    if (stop != null && !stop.isCompleted)
      stop.complete(); // 1) tell our own code
    _cloudCancel?.cancel(
      'stopped by user',
    ); //                 2) hang up the internet call
    final chatId = await tokenStorage.activeChatId();
    await nativeAiService.cancelGeneration(
      chatId,
    ); //          3) tell Android to stop
  }

  /// Turns any error into a plain sentence describing what REALLY happened.
  String _explainError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code != null) return 'Server replied $code: ${e.response?.data}';
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timeout (could not reach the server in time)';
        case DioExceptionType.sendTimeout:
          return 'Send timeout (upload to the server was too slow)';
        case DioExceptionType.receiveTimeout:
          return 'Receive timeout (the server took too long to answer)';
        case DioExceptionType.connectionError:
          return 'Connection error (phone says online but the server is unreachable): ${e.message}';
        default:
          return '${e.type.name}: ${e.message}';
      }
    }
    return e.toString();
  }

  /// A kind message for the person using the app.
  String _friendlyCloudMessage(Object e) {
    if (e.toString().contains('missing_api_key')) {
      return 'The app is missing its API key (developer setup issue).';
    }
    if (e.toString().contains('unexpected_reply_shape')) {
      return 'The server answered in a way the app did not understand. Please try again.';
    }
    if (e is DioException) {
      switch (e.response?.statusCode) {
        case 401:
          return 'Your login could not be renewed. Please sign out and sign in again.';
        case 403:
          return 'The server refused the request (403). The API key may be missing or wrong.';
        case 429:
          return 'Too many requests. Please wait a moment and try again.';
        case 500:
        case 502:
        case 503:
          return 'The server had a problem. Please try again shortly.';
        case 504:
          return 'The server took too long to think. Please try again.';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'The server took too long to answer. Please try again.';
      }
    }
    return 'Could not reach the cloud server. Please check your internet and try again.';
  }
}

// TELEMETRY helpers (private to this file)

/// Collects REAL measurements while the on-phone model works.
@visibleForTesting
class OfflineRun {
  OfflineRun({DeviceEnvelopeSampler? envelope})
    : envelope = envelope ?? DeviceEnvelopeSampler(DeviceTelemetry());

  /// Samples the phone's memory/thermal/battery while this answer runs.
  final DeviceEnvelopeSampler envelope;

  /// Runs only while the on-phone model is busy (the cloud is not included).
  final Stopwatch clock = Stopwatch();

  /// Where we are right now (a word from the contract's error_stage list).
  String stage = 'model_load';

  /// Time spent loading the 2.5 GB model before generation could start.
  int? modelLoadMs;

  /// Clock value when generation (not model loading) began. Timings below are
  /// measured from this point so "time to first token" means what it says.
  int? generationStartedMs;

  int? firstTokenMs; // time to first token, counted from generation start
  int? lastTokenMs; // time the last token arrived, from generation start
  int? outputChars = 0; // how many characters were streamed
  int? nativeOutputTokens; // ONLY set when Android itself reports a count
  int? retrievedPassageCount; // how many passages retrieval returned
  bool toolUsed = false;
  bool toolFailed = false; // a tool call really failed while executing
  bool streamed = false;
  bool nativeCancelled = false;
  String? nativeErrorCode;
  String? nativeErrorStage;

  void observe(AiEvent event) {
    final now = clock.elapsedMilliseconds;
    final relative = now - (generationStartedMs ?? 0);
    final raw = event.raw;

    nativeOutputTokens =
        _firstInt(raw, const [
          'output_tokens',
          'token_count',
          'generated_tokens',
        ]) ??
        nativeOutputTokens;

    // TELEMETRY: Android states the truth about tools on tool_result / completed / error.
    if (raw['tool_used'] == true) toolUsed = true;
    if (raw['tool_error'] == true) toolFailed = true;
    final reportedCount = _firstInt(raw, const [
      'retrieved_passage_count',
      'passage_count',
    ]);
    if (reportedCount != null) retrievedPassageCount = reportedCount;

    switch (event.type) {
      case AiEventType.token:
        streamed = true;
        firstTokenMs ??= relative;
        lastTokenMs = relative;
        outputChars = (outputChars ?? 0) + event.text.length;
        break;
      case AiEventType.retrievalContext:
        // Android sends the passages as "citations" (and their ids as "context_ids").
        final listed =
            raw['passages'] ?? raw['citations'] ?? raw['context_ids'];
        if (listed is List) retrievedPassageCount = listed.length;
        break;
      case AiEventType.toolCallRequested:
        toolUsed = true;
        stage = 'tool_execution';
        break;
      case AiEventType.toolResult:
        if (raw['tool_error'] == true) toolFailed = true;
        stage = 'generation';
        break;
      case AiEventType.cancelled:
        nativeCancelled = true;
        break;
      case AiEventType.error:
        nativeErrorCode = (raw['error_code'] ?? raw['code'])?.toString();
        nativeErrorStage = (raw['error_stage'] ?? raw['stage'])?.toString();
        break;
      default:
        break;
    }
  }

  /// The extra info that goes into `metadata` (contract: offline_inference).
  /// A value we did not really measure is LEFT OUT, never guessed.
  Map<String, Object?> responseMetadata() {
    final tokens = nativeOutputTokens;
    final first = firstTokenMs;
    final last = lastTokenMs;
    final generationStart = generationStartedMs;

    double? tokensPerSecond;
    if (tokens != null &&
        tokens > 1 &&
        first != null &&
        last != null &&
        last > first) {
      tokensPerSecond = double.parse(
        ((tokens - 1) / ((last - first) / 1000)).toStringAsFixed(1),
      );
    }

    return {
      if (tokens != null) 'output_tokens': tokens,
      if (outputChars != null) 'output_chars': outputChars,
      'tool_used': toolUsed,
      'retrieved_passage_count': retrievedPassageCount ?? 0,
      'streamed': streamed,
      if (modelLoadMs != null) 'model_load_ms': modelLoadMs,
      if (first != null) 'time_to_first_token_ms': first,
      if (modelLoadMs != null && first != null)
        'time_to_first_token_from_request_ms': modelLoadMs! + first,
      if (first != null && last != null && last >= first)
        'stream_duration_ms': last - first,
      if (generationStart != null)
        'generation_duration_ms': clock.elapsedMilliseconds - generationStart,
      if (tokensPerSecond != null) 'tokens_per_second': tokensPerSecond,
    };
  }

  /// Everything above + the device envelope measured while the answer ran.
  Future<Map<String, Object?>> fullResponseMetadata() async {
    final envelopeMetadata = await envelope.metadata();
    return {...responseMetadata(), ...envelopeMetadata};
  }

  static int? _firstInt(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final v = raw[key];
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}

/// What went wrong, already translated into the contract's words.
@visibleForTesting
class OfflineFailure {
  const OfflineFailure._({
    this.inferenceCode,
    required this.stage,
    this.runtimeCode,
    this.failureKind,
  });

  /// Fits an offline_inference error (one of the five codes).
  factory OfflineFailure.inference(String code, String stage) =>
      OfflineFailure._(inferenceCode: code, stage: stage);

  /// Does not fit -> becomes a runtime_failure.
  factory OfflineFailure.runtime(String code, String type, String stage) =>
      OfflineFailure._(runtimeCode: code, failureKind: type, stage: stage);

  final String? inferenceCode;
  final String stage;
  final String? runtimeCode;
  final String? failureKind;

  /// runtime_failure only allows these stages (no 'context_build').
  String get runtimeStage =>
      TelemetryContract.failureStages.contains(stage) ? stage : 'generation';
}
