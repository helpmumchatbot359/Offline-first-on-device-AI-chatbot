import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class DiagnosticLogger {
  DiagnosticLogger();

  String? _currentOfflineCycleId;
  String _currentNetworkState = 'stable_connectivity';

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

  Future<void> logEvent({
    required String logType,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      final logDir = await _logDir();
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final file = File(p.join(logDir.path, 'diagnostics-$dateStr.jsonl'));
      final logEntry = {
        'logId': 'log-${const Uuid().v4()}',
        'offlineCycleId': currentOfflineCycleId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'logType': logType,
        'networkState': _currentNetworkState,
        'metrics': metrics,
      };
      await file.writeAsString('${jsonEncode(logEntry)}\n', mode: FileMode.append);
    } catch (_) {
      // Diagnostic logging must never crash the app.
    }
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