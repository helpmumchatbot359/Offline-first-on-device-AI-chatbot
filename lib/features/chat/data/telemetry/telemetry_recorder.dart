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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../local/chat_local_data_source.dart';
import '../local/diagnostic_logger.dart';
import '../local/entities/local_telemetry_entity.dart';
import 'device_telemetry.dart';

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

    // The device envelope is added to EVERY event by TelemetryRecorder.
    // It is optional at validation time (so old queued events can still be
    // cleaned up), but when present it must be an object.
    if (meta['device'] != null) {
      need(meta['device'] is Map, 'metadata.device must be an object');
    }
    if (meta['memory'] != null) {
      need(meta['memory'] is Map, 'metadata.memory must be an object');
    }
    if (meta['thermal'] != null) {
      need(meta['thermal'] is Map, 'metadata.thermal must be an object');
    }
    if (meta['battery'] != null) {
      need(meta['battery'] is Map, 'metadata.battery must be an object');
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
        // ---- TOOL / RETRIEVAL TELEMETRY ----
        // tool_used is always required (true or false).
        // retrieved_passage_count is required for EVERY answer now, and 0 is a
        // real answer ("the model got no passages"), never "missing".
        need(meta['tool_used'] is bool, 'offline_inference: metadata.tool_used is required (true or false)');
        need(meta['retrieved_passage_count'] is int && (meta['retrieved_passage_count'] as int) >= 0,
            'offline_inference: metadata.retrieved_passage_count is required (0 is allowed)');
        if (e.errorCode == 'TOOL_ERROR' || meta['error_stage'] == 'tool_execution') {
          // A tool error means a tool call happened, so tool_used can never be false.
          need(meta['tool_used'] == true,
              'offline_inference: tool_used must be true when error_code is TOOL_ERROR or error_stage is tool_execution');
        }
        if (meta['retrieved_passage_count'] != null) {
          need(meta['retrieved_passage_count'] is int && (meta['retrieved_passage_count'] as int) >= 0,
              'offline_inference: retrieved_passage_count must be a whole number (0 is allowed)');
        }
        if (meta['output_tokens'] != null) {
          need(meta['output_tokens'] is int && (meta['output_tokens'] as int) >= 0,
              'offline_inference: output_tokens must be a whole number');
        }
        // Timing fields: present only when we really measured them.
        for (final key in const [
          'model_load_ms',
          'time_to_first_token_ms',
          'time_to_first_token_from_request_ms',
          'stream_duration_ms',
          'generation_duration_ms',
          'output_chars',
        ]) {
          final value = meta[key];
          if (value != null) {
            need(value is int && value >= 0, 'offline_inference: metadata.$key must be a whole number >= 0');
          }
        }
        if (meta['tokens_per_second'] != null) {
          need(meta['tokens_per_second'] is num && (meta['tokens_per_second'] as num) >= 0,
              'offline_inference: tokens_per_second must be a number >= 0');
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
  TelemetryRecorder(
    this._local, {
    DeviceTelemetry? deviceTelemetry,
    DiagnosticLogger? diagnosticLogger,
  })  : _deviceTelemetry = deviceTelemetry ?? DeviceTelemetry(),
        // ignore: prefer_initializing_formals
        _diagnosticLogger = diagnosticLogger;

  final ChatLocalDataSource _local;
  final DeviceTelemetry _deviceTelemetry;
  final DiagnosticLogger? _diagnosticLogger;
  static const _uuid = Uuid();

  /// Called right after an event is safely stored on the phone.
  /// main.dart points this at SyncService.syncAll(), so a freshly created
  /// offline_inference is uploaded immediately instead of waiting for the next
  /// scheduled sync. If there is no network, syncAll() does nothing.
  void Function()? onEventQueued;

  /// Read-only access for the chat repository, which samples the envelope
  /// while an on-phone answer is running.
  DeviceTelemetry get deviceTelemetry => _deviceTelemetry;

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
      // EVERY event gets the device envelope. Per-inference values (memory at
      // start, peak PSS, thermal, battery) win over the live snapshot because
      // they describe the answer, not the moment this line ran.
      Map<String, Object?> enrichedMetadata;
      try {
        enrichedMetadata = await _withDeviceEnvelope(metadata);
      } catch (e) {
        // A broken native snapshot must NOT throw the event away. Send the
        // event without the envelope instead; the server still gets the row.
        debugPrint('TELEMETRY ENVELOPE FAILED: $e');
        enrichedMetadata = {...metadata};
      }

      // Remove every null/nested-null field. Example: a successful answer used
      // to send "error_stage": null. A strict backend can reject the WHOLE
      // batch for that one field, which made good inference events disappear.
      enrichedMetadata = withoutNulls(enrichedMetadata);

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
        metadataJson: jsonEncode(enrichedMetadata),
        syncState: 'pending',
      );

      final problems = TelemetryContract.validate(event);
      if (problems.isNotEmpty) {
        // Storing it would make the backend reject the whole upload.
        debugPrint('TELEMETRY NOT SAVED (breaks the contract): $problems');
        unawaited(_logDiagnostic('telemetry_event_rejected', {
          'event_uuid': event.eventUuid,
          'event_type': event.eventType,
          'chat_id': event.chatId,
          'problems': problems,
        }));
        return;
      }
      await _local.saveTelemetryEvent(event);

      // Try to upload it right away (the sync service ignores this when the
      // phone has no network). Never let this call break the chat.
      try {
        onEventQueued?.call();
      } catch (_) {}

      // AUDIT TRAIL. This proves on the phone that the event really reached
      // the local queue, before any network request happens.
      unawaited(_logDiagnostic('telemetry_event_saved', {
        'event_uuid': event.eventUuid,
        'event_type': event.eventType,
        'chat_id': event.chatId,
        'outcome': event.outcome,
        'latency_ms': event.latencyMs,
        'metadata_bytes': event.metadataJson.length,
      }));

      if (kDebugMode) {
        // Debug builds only: lets you SEE exactly what was stored (no message
        // text is ever in it). The metadata is printed in chunks because a
        // single very long line is cut off by logcat / the terminal.
        final metadata = event.metadataJson;
        debugPrint('TELEMETRY SAVED ${event.eventType} outcome=${event.outcome} '
            'code=${event.errorCode} metadata_length=${metadata.length}');
        const chunkSize = 700;
        for (var start = 0; start < metadata.length; start += chunkSize) {
          final end = (start + chunkSize < metadata.length) ? start + chunkSize : metadata.length;
          final part = start ~/ chunkSize + 1;
          debugPrint('TELEMETRY META[$part] ${metadata.substring(start, end)}');
        }
      }
    } catch (e) {
      // Telemetry must NEVER crash the chat.
      debugPrint('TELEMETRY SAVE FAILED: $e');
      unawaited(_logDiagnostic('telemetry_event_failed', {
        'event_type': eventType,
        'chat_id': chatId,
        'error': e.toString().length > 500 ? e.toString().substring(0, 500) : e.toString(),
      }));
    }
  }

  /// Drops null values at every level. A missing optional field is safe; a
  /// present field with value null is what strict JSON schemas often refuse.
  static Map<String, Object?> withoutNulls(Map<String, Object?> value) {
    final cleaned = <String, Object?>{};
    for (final entry in value.entries) {
      final item = _withoutNullsValue(entry.value);
      if (item != null) cleaned[entry.key] = item;
    }
    return cleaned;
  }

  static Object? _withoutNullsValue(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      final cleaned = <String, Object?>{};
      for (final entry in value.entries) {
        final item = _withoutNullsValue(entry.value);
        if (item != null) cleaned[entry.key.toString()] = item;
      }
      return cleaned;
    }
    if (value is List) {
      return value.map(_withoutNullsValue).where((item) => item != null).toList();
    }
    return value;
  }

  Future<void> _logDiagnostic(String logType, Map<String, dynamic> metrics) async {
    final logger = _diagnosticLogger;
    if (logger == null) return;
    await logger.logEvent(logType: logType, metrics: metrics);
  }

  /// Public wrapper used by the sync service to repair events queued by an
  /// older build that did not have the device envelope yet.
  Future<Map<String, Object?>> envelopeMetadata([
    Map<String, Object?> metadata = const {},
  ]) =>
      _withDeviceEnvelope(metadata);

  /// Merges the live device snapshot under the caller's metadata.
  /// Caller values always win, so a fully measured inference envelope is kept.
  ///
  /// The snapshot is converted through [DeviceEnvelope] first. That guarantees
  /// EVERY event (not only inferences) uses the same metadata shape:
  ///   device  : manufacturer, model, android_api, ram_total_mb, ram_class, backend
  ///   memory  : available_mb_at_start, process_pss_mb_at_start, peak_process_pss_mb
  ///   thermal : status_at_start, status_name_at_start, headroom_at_start
  ///   battery : percent, temperature_c, charging
  Future<Map<String, Object?>> _withDeviceEnvelope(
    Map<String, Object?> metadata,
  ) async {
    Map<String, Object?> snapshot;
    try {
      snapshot = await _deviceTelemetry.snapshot();
    } catch (_) {
      snapshot = _deviceTelemetry.fallbackSnapshot();
    }

    final device = _asMap(snapshot['device']);
    final memory = _asMap(snapshot['memory']);
    final currentPss = _asInt(memory['process_pss_mb']);
    final base = DeviceEnvelope(
      device: device.isEmpty ? await _deviceTelemetry.deviceInfo() : device,
      start: snapshot,
      peakProcessPssMb: currentPss,
    ).toMetadata();

    final merged = <String, Object?>{...base};
    for (final entry in metadata.entries) {
      final current = merged[entry.key];
      final incoming = entry.value;
      if (current is Map && incoming is Map) {
        merged[entry.key] = <String, Object?>{
          ...current.map((k, v) => MapEntry(k.toString(), v)),
          ...incoming.map((k, v) => MapEntry(k.toString(), v)),
        };
      } else {
        merged[entry.key] = incoming;
      }
    }

    // Absolute guarantee: every event carries the static device block.
    if (merged['device'] is! Map) {
      merged['device'] = await _deviceTelemetry.deviceInfo();
    }
    return merged;
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, Object?>{};
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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
    required String outcome,
    String? errorCode,
    String? errorStage,
    Map<String, Object?> responseMetadata = const {},
  }) {
    final metadata = <String, Object?>{
      if (errorStage != null) 'error_stage': errorStage,
      ...responseMetadata,
    };
    if (metadata['tool_used'] is! bool) {
      metadata['tool_used'] = false;
    }
    final passages = metadata['retrieved_passage_count'];
    if (passages is! int || passages < 0) {
      metadata['retrieved_passage_count'] = 0;
    }

    return _save(
      eventType: TelemetryContract.offlineInference,
      chatId: chatId,
      modelVersion: modelVersion,
      latencyMs: latencyMs,
      outcome: outcome,
      errorCode: errorCode,
      connectivity: 'offline',
      metadata: metadata,
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
    Map<String, Object?> extraMetadata = const {},
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
        ...extraMetadata,
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