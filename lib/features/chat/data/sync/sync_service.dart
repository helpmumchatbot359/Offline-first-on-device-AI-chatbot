import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/security/token_storage.dart';
import '../ai/model_setup_service.dart';
import '../local/chat_local_data_source.dart';
import '../local/diagnostic_logger.dart';
import '../local/entities/local_telemetry_entity.dart';
import '../telemetry/telemetry_recorder.dart';

class SyncService {
  SyncService(
    this._apiClient,
    this._connectivity,
    this._localDataSource,
    this._diagnosticLogger, {
    required this._telemetry,
    required this._tokenStorage,
    required this._modelSetupService,
  });

  final ApiClient _apiClient;
  final Connectivity _connectivity;
  final ChatLocalDataSource _localDataSource;
  final DiagnosticLogger _diagnosticLogger;
  final TelemetryRecorder _telemetry;
  final TokenStorage _tokenStorage;
  final ModelSetupService _modelSetupService;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;

  /// Send telemetry in small batches so one upload is never huge,
  /// and an interrupted upload only has to repeat a small piece.
  static const _telemetryBatchSize = 50;
  static const _maxBatchesPerSync = 20;

  // What the network looked like last time we checked (to detect "online -> offline").
  List<ConnectivityResult>? _lastResults;
  // When the connection changed recently (to tell "intermittent" from "online").
  final List<DateTime> _recentChanges = [];

  // ---------------------------------------------------------------------------
  // Start listening to the network
  // ---------------------------------------------------------------------------
  void startBackgroundSync() {
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      _lastResults = await _connectivity.checkConnectivity();
    } catch (_) {}
    _subscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    unawaited(syncAll());
  }

  static bool _hasInternet(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final previous = _lastResults;
    final wasOnline = previous == null ? null : _hasInternet(previous);
    final isOnline = _hasInternet(results);
    _lastResults = results;

    // Only real changes count. (wifi -> cellular is not "offline".)
    if (wasOnline == isOnline) return;

    final changesBefore = _countRecentChanges();
    _recentChanges.add(DateTime.now());

    if (isOnline) {
      _diagnosticLogger.endOfflineCycle('reconnection', {'status': 'connected'});
      await syncAll();
    } else {
      _diagnosticLogger.startOfflineCycle('none');

      // THE moment for offline_started: it was available, now it is not.
      // `wasOnline == null` means we never knew the first state: not a change.
      if (wasOnline == true) {
        await _telemetry.recordOfflineStarted(
          chatId: await _safeActiveChatId(),
          modelVersion: await _safeModelVersion(),
          // 2+ changes in the last minute = a flickering connection.
          previousConnectivity: changesBefore >= 2 ? 'intermittent' : 'online',
          // The kind of network we just LOST.
          networkType: _networkTypeOf(previous ?? const []),
        );
      }
    }
  }

  int _countRecentChanges() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    _recentChanges.removeWhere((t) => t.isBefore(cutoff));
    return _recentChanges.length;
  }

  static String _networkTypeOf(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi)) return 'wifi';
    if (r.contains(ConnectivityResult.mobile)) return 'cellular';
    return 'unknown';
  }

  Future<String?> _safeActiveChatId() async {
    try {
      return await _tokenStorage.activeChatId();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _safeModelVersion() async {
    try {
      return await _modelSetupService.existingPath() != null ? TelemetryContract.modelVersion : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _connectivityLabel() async {
    try {
      final r = await _connectivity.checkConnectivity();
      if (!_hasInternet(r)) return 'offline';
      return _countRecentChanges() >= 2 ? 'intermittent' : 'online';
    } catch (_) {
      return 'unknown';
    }
  }

  // ---------------------------------------------------------------------------
  // Sync everything. Each part runs ON ITS OWN: if chat sync fails, telemetry
  // sync still runs (before, one failure stopped everything behind it).
  // ---------------------------------------------------------------------------
  Future<void> syncAll() async {
    if (_isSyncing) return;

    // No network = we do not even try, so nothing "failed" and no sync_error is made.
    try {
      if (!_hasInternet(await _connectivity.checkConnectivity())) return;
    } catch (_) {}

    _isSyncing = true;
    final stopwatch = Stopwatch()..start();
    try {
      final chatsOk = await _syncPendingChats();
      final telemetryOk = await _syncPendingTelemetry();
      final diagnosticsOk = await _syncPendingDiagnostics();
      stopwatch.stop();
      _diagnosticLogger.logEvent(
        logType: 'synchronization_measurement',
        metrics: {
          'sync_success': chatsOk && telemetryOk && diagnosticsOk,
          'acknowledgement_time_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } finally {
      _isSyncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // CHAT sync (logic unchanged, but a failure is now recorded as sync_error)
  // ---------------------------------------------------------------------------
  Future<bool> _syncPendingChats() async {
    final pending = await _localDataSource.getPendingMessages();
    if (pending.isEmpty) return true;

    final grouped = <String, List<Map<String, dynamic>>>{};
    final idsByChat = <String, List<int>>{};
    for (final msg in pending) {
      grouped.putIfAbsent(msg.chatId, () => []).add({
        'message': msg.message,
        'ai_response': msg.aiResponse,
        'date': msg.date,
      });
      idsByChat.putIfAbsent(msg.chatId, () => []).add(msg.id);
    }

    final clock = Stopwatch()..start();
    try {
      final response = await _apiClient.dio.post('/v1/chats/sync', data: grouped);
      if (_ok(response)) {
        for (final ids in idsByChat.values) {
          await _localDataSource.markMessagesAcknowledged(ids);
        }
      }
      return true;
    } catch (e) {
      clock.stop();
      final failure = classifySyncError(e);
      await _recordSyncError(
        target: 'chat',
        code: failure.code,
        status: failure.status,
        latencyMs: clock.elapsedMilliseconds,
        chatId: grouped.keys.first, // a chat that was in the failed batch
      );
      _diagnosticLogger.logEvent(logType: 'runtime_failure_detail', metrics: {
        'failure_type': 'sync_error',
        'error_message': _describe(e),
        'duration_ms': clock.elapsedMilliseconds,
      });
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // TELEMETRY sync
  //  * only events that follow the contract are sent
  //  * sent in small batches, oldest first
  //  * ONLY the UUIDs the backend sends back are marked as acknowledged
  //  * anything not acknowledged stays 'pending' and is retried with the SAME
  //    event_uuid, so an interrupted upload can never create duplicates
  // ---------------------------------------------------------------------------
  Future<bool> _syncPendingTelemetry() async {
    await _dropEventsTheBackendWouldReject();

    for (var round = 0; round < _maxBatchesPerSync; round++) {
      final batch = await _localDataSource.getPendingTelemetryEvents(limit: _telemetryBatchSize);
      if (batch.isEmpty) return true;

      final clock = Stopwatch()..start();
      try {
        final payload = batch.map(_toPayload).toList();
        final response = await _apiClient.dio.post('/v1/telemetry', data: payload);

        final acknowledged = <String>{};
        final data = response.data;
        if (data is Map && data['acknowledged_event_uuids'] is List) {
          for (final u in data['acknowledged_event_uuids'] as List) {
            acknowledged.add(u.toString());
          }
        }

        // Only trust UUIDs that we really sent in THIS batch.
        final sent = batch.map((e) => e.eventUuid).toSet();
        final confirmed = acknowledged.intersection(sent).toList();
        await _localDataSource.markTelemetryAcknowledged(confirmed);

        if (confirmed.length < batch.length) {
          // The server did not confirm everything. Do NOT pretend it did
          // (the old code marked everything as done on any 200 reply).
          clock.stop();
          await _recordSyncError(
            target: 'telemetry',
            code: 'SERVER_ERROR',
            status: response.statusCode,
            latencyMs: clock.elapsedMilliseconds,
          );
          return false;
        }
      } catch (e) {
        clock.stop();
        final failure = classifySyncError(e);
        await _recordSyncError(
          target: 'telemetry',
          code: failure.code,
          status: failure.status,
          latencyMs: clock.elapsedMilliseconds,
        );
        _diagnosticLogger.logEvent(logType: 'runtime_failure_detail', metrics: {
          'failure_type': 'sync_error',
          'error_message': _describe(e),
          'duration_ms': clock.elapsedMilliseconds,
        });
        return false; // events stay pending, retried next time
      }
    }
    return true;
  }

  /// Exactly the JSON shape of the contract (section 4).
  Map<String, dynamic> _toPayload(LocalTelemetryEvent e) => {
        'event_uuid': e.eventUuid,
        'event_type': e.eventType,
        'chat_id': e.chatId,
        'date': e.date,
        'model_version': e.modelVersion,
        'latency_ms': e.latencyMs,
        'outcome': e.outcome,
        'error_code': e.errorCode,
        'connectivity': e.connectivity,
        'metadata': jsonDecode(e.metadataJson),
      };

  /// SAFETY NET. Old events saved by the previous version of the app
  /// (event_type 'online_inference', error_code 'offline_mode', ...) can never
  /// be accepted. If they stay in the queue they are sent again and again and
  /// the backend refuses the WHOLE batch each time, so good events never arrive.
  /// This removes only the events that break the contract.
  Future<void> _dropEventsTheBackendWouldReject() async {
    final pending = await _localDataSource.getPendingTelemetryEvents();
    final badIds = <int>[];
    for (final e in pending) {
      final problems = TelemetryContract.validate(e);
      if (problems.isNotEmpty) {
        badIds.add(e.id);
        debugPrint('TELEMETRY DROPPED (${e.eventType}): $problems');
      }
    }
    if (badIds.isEmpty) return;
    await _localDataSource.removeTelemetry(badIds);
    _diagnosticLogger.logEvent(
      logType: 'telemetry_dropped_invalid',
      metrics: {'count': badIds.length},
    );
  }

  Future<void> _recordSyncError({
    required String target, // chat | telemetry
    required String code,
    int? status,
    required int latencyMs,
    String? chatId,
  }) async {
    await _telemetry.recordSyncError(
      chatId: target == 'telemetry' ? null : chatId,
      latencyMs: latencyMs,
      errorCode: code,
      connectivity: await _connectivityLabel(),
      syncTarget: target,
      pendingChatCount: await _localDataSource.countPendingMessages(),
      pendingEventCount: await _localDataSource.countPendingTelemetry(),
      httpStatus: status,
    );
  }

  /// Turns "whatever went wrong" into ONE of the five codes in the contract.
  static ({String code, int? status}) classifySyncError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status != null) {
        if (status == 401 || status == 403) return (code: 'UNAUTHORIZED', status: status);
        if (status == 400 || status == 413 || status == 422) {
          return (code: 'INVALID_PAYLOAD', status: status);
        }
        return (code: 'SERVER_ERROR', status: status);
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return (code: 'SYNC_TIMEOUT', status: null);
        default:
          return (code: 'NETWORK_UNAVAILABLE', status: null);
      }
    }
    // Not a network problem: our own code failed while preparing the data.
    return (code: 'INVALID_PAYLOAD', status: null);
  }

  // ---------------------------------------------------------------------------
  // DIAGNOSTIC logs. NOTE: '/v1/diagnostic-logs' is NOT in the contract you
  // were sent. It now runs on its own, so if that endpoint does not exist it
  // can no longer disturb telemetry. Ask the backend engineer if he wants it.
  // ---------------------------------------------------------------------------
  Future<bool> _syncPendingDiagnostics() async {
    try {
      final pending = await _diagnosticLogger.readPending();
      if (pending.byCycle.isEmpty) return true;

      var allOk = true;
      for (final entry in pending.byCycle.entries) {
        final response = await _apiClient.dio.post(
          '/v1/diagnostic-logs',
          data: {'offline_cycle_id': entry.key, 'records': entry.value},
        );
        if (!_ok(response)) allOk = false;
      }
      if (allOk) await _diagnosticLogger.markUploaded(pending.files);
      return allOk;
    } catch (e) {
      debugPrint('DIAGNOSTIC UPLOAD FAILED: ${_describe(e)}');
      return false;
    }
  }

  static String _describe(Object e) {
    if (e is DioException) {
      return '${e.requestOptions.method} ${e.requestOptions.path} -> '
          '${e.response?.statusCode ?? e.type.name}: ${e.response?.data ?? e.message}';
    }
    return e.toString();
  }

  static bool _ok(Response r) => (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;

  void stop() => _subscription?.cancel();
}