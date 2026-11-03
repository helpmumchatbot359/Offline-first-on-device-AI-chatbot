// Tests for the device/runtime block inside diagnostic-log metrics.
//
// The diagnostics table (/v1/diagnostic-logs) must answer:
//   * which phone and how much RAM?          -> metrics.device
//   * how much free memory / process PSS?    -> metrics.memory
//   * how hot did it get?                    -> metrics.thermal
//   * battery state?                         -> metrics.battery
//   * which CPU/backend?                     -> metrics.device.cpu_abi/backend
//   * how long did the model take to load?   -> metrics.model_load_ms
//
// Run with: flutter test test/diagnostic_logger_metrics_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/local/diagnostic_logger.dart';
import 'package:mama_ai/features/chat/data/telemetry/device_telemetry.dart';

/// Pretends to be Android, so the test never needs a real phone.
class FakeDeviceTelemetry extends DeviceTelemetry {
  @override
  Future<Map<String, Object?>> snapshot() async => {
        'device': {
          'manufacturer': 'Samsung',
          'brand': 'samsung',
          'model': 'SM-A546B',
          'device': 'a54x',
          'android_api': 35,
          'android_release': '15',
          'cpu_abi': 'arm64-v8a',
          'cpu_cores': 8,
          'ram_total_mb': 8192,
          'ram_class': '8GB',
          'backend': 'cpu',
        },
        'memory': {
          'available_mb': 1079,
          'total_mb': 8192,
          'threshold_mb': 200,
          'low_memory': false,
          'process_pss_mb': 1200,
        },
        'thermal': {
          'status': 2,
          'status_name': 'moderate',
          'headroom': 0.4,
        },
        'battery': {
          'percent': 80,
          'temperature_c': 31.5,
          'charging': false,
          'plugged': false,
        },
      };
}

void main() {
  test('ordinary diagnostic record gets the whole runtime envelope', () async {
    final logger = DiagnosticLogger(deviceTelemetry: FakeDeviceTelemetry());

    final metrics = await logger.withRuntimeDiagnostics({
      'latency_ms': 1200,
      'success': true,
      'model_load_ms': 3912,
    });

    final device = metrics['device'] as Map;
    expect(device['model'], 'SM-A546B');
    expect(device['ram_total_mb'], 8192);
    expect(device['ram_class'], '8GB');
    expect(device['cpu_abi'], 'arm64-v8a');
    expect(device['backend'], 'cpu');

    final memory = metrics['memory'] as Map;
    expect(memory['available_mb_at_start'], 1079);
    expect(memory['process_pss_mb_at_start'], 1200);
    expect(memory['peak_process_pss_mb'], 1200);

    final thermal = metrics['thermal'] as Map;
    expect(thermal['status_name_at_start'], 'moderate');

    final battery = metrics['battery'] as Map;
    expect(battery['percent'], 80);
    expect(battery['temperature_c'], 31.5);

    expect(metrics['model_load_ms'], 3912);
    expect(metrics['latency_ms'], 1200);
    expect(metrics['success'], isTrue);
  });

  test('measured inference values win over the live snapshot', () async {
    final logger = DiagnosticLogger(deviceTelemetry: FakeDeviceTelemetry());

    final metrics = await logger.withRuntimeDiagnostics({
      'memory': {
        'available_mb_at_start': 5340,
        'peak_process_pss_mb': 1442,
        'available_mb_at_end': 4000,
      },
      'thermal': {
        'status_at_start': 1,
        'status_at_end': 3,
      },
    });

    final memory = metrics['memory'] as Map;
    // Measured values survive...
    expect(memory['available_mb_at_start'], 5340);
    expect(memory['peak_process_pss_mb'], 1442);
    expect(memory['available_mb_at_end'], 4000);
    // ...and the raw live numbers are still present.
    expect(memory['available_mb'], 1079);
    expect(memory['process_pss_mb'], 1200);

    final thermal = metrics['thermal'] as Map;
    expect(thermal['status_at_start'], 1);
    expect(thermal['status_at_end'], 3);
    expect(thermal['status_name_at_start'], 'moderate');
  });
}
