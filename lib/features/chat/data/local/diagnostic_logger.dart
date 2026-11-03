import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../telemetry/device_telemetry.dart';

class DiagnosticLogger {
  DiagnosticLogger({DeviceTelemetry? deviceTelemetry})
      : _deviceTelemetry = deviceTelemetry ?? DeviceTelemetry();

  /// Reads the phone/runtime facts (model, RAM, memory, PSS, thermal,
  /// battery, CPU/backend). Every diagnostic record gets this block, so the
  /// server can explain a failure without asking which phone was used.
  final DeviceTelemetry _deviceTelemetry;

  String? _currentOfflineCycleId;
  String _currentNetworkState = 'stable_connectivity';

  /// Highest process PSS this logger has seen. For records with no sampler

  int? _peakProcessPssMb;

  String get currentOfflineCycleId => _currentOfflineCycleId ??= 'cycle-${const Uuid().v4()}';

  void startOfflineCycle(String networkType) {
    _currentOfflineCycleId = 'cycle-${const Uuid().v4()}';
    _currentNetworkState = 'no_internet';
    logEvent(
      logType: 'cycle_started',
      metrics: {'network_type': networkType, 'offline_cycle_id': _currentOfflineCycleId},
    );
  }

  void endOfflineCycle(String networkState, Map<String, dynamic> summaryMetrics) {
    _currentNetworkState = networkState;
    logEvent(
      logType: 'cycle_ended',
      metrics: {...summaryMetrics, 'offline_cycle_id': _currentOfflineCycleId},
    );
    _currentOfflineCycleId = null;
  }

  Future<Directory> _logDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory(p.join(dir.path, 'diagnostic_logs'));
    if (!await logDir.exists()) await logDir.create(recursive: true);
    return logDir;
  }

  /// Adds the device/runtime block to the metrics of ONE diagnostic record.
  ///
  /// The shape is the SAME shape telemetry uses:
  ///   device  : manufacturer, model, ram_total_mb, ram_class, cpu_abi, backend
  ///   memory  : available_mb_at_start, process_pss_mb_at_start,
  ///             peak_process_pss_mb, ...
  ///   thermal : status_at_start, status_name_at_start, headroom_at_start
  ///   battery : percent, temperature_c, charging
  ///
  /// If the caller already measured a whole inference (start snapshot, peak PSS
  /// and end snapshot), those values win because they describe what really
  /// happened while the answer was produced.
  Future<Map<String, Object?>> withRuntimeDiagnostics(
    Map<String, dynamic> metrics,
  ) async {
    final snapshot = await _safeSnapshot();
    return _runtimeDiagnosticsFromSnapshot(metrics, snapshot);
  }

  /// Same as [withRuntimeDiagnostics], but uses a snapshot we already took.
  /// Used by readPending() so one upload takes only ONE native snapshot.
  Map<String, Object?> _runtimeDiagnosticsFromSnapshot(
    Map<String, dynamic> metrics,
    Map<String, Object?> snapshot,
  ) {
    final device = _asMap(snapshot['device']);
    final memory = _asMap(snapshot['memory']);
    final thermal = _asMap(snapshot['thermal']);

    final currentPss = _asInt(memory['process_pss_mb']);
    if (currentPss != null && currentPss > (_peakProcessPssMb ?? -1)) {
      _peakProcessPssMb = currentPss;
    }

    // Reuse the exact envelope builder used by telemetry, so the diagnostics
    // table and the telemetry table speak the same language.
    final envelope = DeviceEnvelope(
      device: device.isEmpty ? _deviceTelemetry.fallbackDevice() : device,
      start: snapshot,
      peakProcessPssMb: _peakProcessPssMb ?? currentPss,
    ).toMetadata();

    // Keep the raw "right now" numbers too. The *_at_start names are kept
    // because that is the shape the backend asked for.
    if (memory.isNotEmpty) {
      final block = _asMap(envelope['memory']);
      block['available_mb'] = memory['available_mb'];
      block['total_mb'] = memory['total_mb'];
      block['threshold_mb'] = memory['threshold_mb'];
      block['low_memory'] = memory['low_memory'];
      block['process_pss_mb'] = memory['process_pss_mb'];
      block['process_pss_mb_at_start'] ??= memory['process_pss_mb'];
      block['peak_process_pss_mb'] ??= memory['process_pss_mb'];
      envelope['memory'] = _withoutNulls(block);
    }
    if (thermal.isNotEmpty) {
      final block = _asMap(envelope['thermal']);
      block['status'] = thermal['status'];
      block['status_name'] = thermal['status_name'];
      block['headroom'] = thermal['headroom'];
      block['status_at_start'] ??= thermal['status'];
      block['status_name_at_start'] ??= thermal['status_name'];
      block['headroom_at_start'] ??= thermal['headroom'];
      envelope['thermal'] = _withoutNulls(block);
    }

    return _deepMerge(envelope, metrics);
  }

  Future<Map<String, Object?>> _safeSnapshot() async {
    try {
      return await _deviceTelemetry.snapshot();
    } catch (_) {
      // Never lose a diagnostic record because a native call failed.
      return _deviceTelemetry.fallbackSnapshot();
    }
  }

  Future<void> logEvent({
    required String logType,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      final enrichedMetrics = await withRuntimeDiagnostics(metrics);
      final logDir = await _logDir();
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final file = File(p.join(logDir.path, 'diagnostics-$dateStr.jsonl'));
      final logEntry = {
        'logId': 'log-${const Uuid().v4()}',
        'offlineCycleId': currentOfflineCycleId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'logType': logType,
        'networkState': _currentNetworkState,
        // device + memory + thermal + battery + everything the caller sent.
        'metrics': enrichedMetrics,
      };
      await file.writeAsString('${jsonEncode(logEntry)}\n', mode: FileMode.append);
    } catch (_) {
      // Diagnostic logging must never crash the app.
    }
  }

  /// Maps are merged one level deep: caller values win, but the device block
  /// is never thrown away just because the caller sent a "memory" map.
  static Map<String, Object?> _deepMerge(
    Map<String, Object?> base,
    Map<String, dynamic> extra,
  ) {
    final merged = <String, Object?>{...base};
    for (final entry in extra.entries) {
      final current = merged[entry.key];
      final incoming = entry.value;
      if (current is Map && incoming is Map) {
        merged[entry.key] = <String, Object?>{
          ...current.map((key, value) => MapEntry(key.toString(), value)),
          ...incoming.map((key, value) => MapEntry(key.toString(), value)),
        };
      } else {
        merged[entry.key] = incoming;
      }
    }
    return merged;
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, Object?>{};
  }

  static Map<String, Object?> _withoutNulls(Map<String, Object?> value) =>
      value..removeWhere((_, item) => item == null);

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Reads every not-yet-uploaded log file and groups the records by offline cycle,
  /// converted to the snake_case shape that POST /v1/diagnostic-logs expects.
  /// Returns {cycleId: [record, ...]} and the files that were read.
  Future<({Map<String, List<Map<String, dynamic>>> byCycle, List<File> files})>
      readPending() async {
    final byCycle = <String, List<Map<String, dynamic>>>{};
    final files = <File>[];
    try {
      final logDir = await _logDir();
      await for (final entity in logDir.list()) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        files.add(entity);
        for (final line in await entity.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            final m = jsonDecode(line) as Map<String, dynamic>;
            final cycle = (m['offlineCycleId'] ?? 'cycle-unknown').toString();
            byCycle.putIfAbsent(cycle, () => []).add({
              'log_id': m['logId'],
              'timestamp': m['timestamp'],
              'log_type': m['logType'],
              'network_state': m['networkState'],
              'metrics': m['metrics'] ?? <String, dynamic>{},
            });
          } catch (_) {/* skip a broken line */}
        }
      }
    } catch (_) {}

    // SAFETY NET: records written by an older app version have no device
    // block. Enrich them at upload time as well, so the table always receives
    // the runtime facts. One snapshot is shared by every record in this batch.
    if (byCycle.isNotEmpty) {
      try {
        final snapshot = await _safeSnapshot();
        for (final records in byCycle.values) {
          for (final record in records) {
            record['metrics'] = _runtimeDiagnosticsFromSnapshot(
              _asMap(record['metrics']),
              snapshot,
            );
          }
        }
      } catch (_) {
        // If this fails, upload the records exactly as they were written.
      }
    }
    return (byCycle: byCycle, files: files);
  }

  /// After the server said 200, rename the files so they are not sent twice.
  Future<void> markUploaded(List<File> files) async {
    for (final f in files) {
      try {
        await f.rename('${f.path}.sent');
      } catch (_) {}
    }
  }
}