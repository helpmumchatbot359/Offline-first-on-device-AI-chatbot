// NEW FILE -> lib/features/chat/data/telemetry/device_telemetry.dart
//
// WHY THIS FILE EXISTS (read this first, beginner friendly)
// ---------------------------------------------------------
// The telemetry contract now wants a "device envelope" on EVERY event:
//
//   "metadata": {
//     "device":  { manufacturer, model, android_api, ram_total_mb,
//                  ram_class, backend, ... },
//     "memory":  { available_mb_at_start, peak_process_pss_mb, ... },
//     "thermal": { status, status_name, headroom },
//     "battery": { percent, temperature_c, charging }
//   }
//
// Flutter/Dart cannot read most of that by itself (RAM class, PSS, thermal
// status and battery temperature are Android-only), so:
//
//   1. DeviceTelemetry        -> asks a small Android MethodChannel
//                                ("mama_ai/device_info") for ONE snapshot.
//   2. DeviceEnvelope         -> turns "start snapshot" + "peak snapshot" into
//                                the exact metadata shape above.
//   3. DeviceEnvelopeSampler  -> samples while an answer is being generated so
//                                we can report the PEAK process memory, not
//                                just a single lucky reading.
//
// Everything degrades gracefully: if the app runs somewhere without the native
// channel (unit tests, desktop), we still return a small honest fallback so the
// telemetry event is never lost.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads the phone's device / memory / thermal / battery state.
class DeviceTelemetry {
  DeviceTelemetry({
    this.backend = 'cpu',
    this.timeout = const Duration(milliseconds: 900),
  });

  /// Which inference backend the app uses. The Android runtime currently uses
  /// the CPU backend, so that is the default.
  final String backend;

  /// A native call must never freeze telemetry forever.
  final Duration timeout;

  static const MethodChannel _channel = MethodChannel('mama_ai/device_info');

  Map<String, Object?>? _cachedDevice;

  /// Backend name that goes into metadata.device.backend.
  String get backendName => backend;

  /// One full snapshot: { device, memory, thermal, battery }.
  Future<Map<String, Object?>> snapshot() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('snapshot', {'backend': backend})
          .timeout(timeout);
      if (raw != null && raw.isNotEmpty) {
        final normalized = _asMap(raw);
        final device = _asMap(normalized['device']);
        if (device.isNotEmpty) _cachedDevice = device;
        return normalized;
      }
    } on MissingPluginException {
      // Not running on Android (or the channel was not registered).
    } on PlatformException catch (e) {
      debugPrint('DEVICE TELEMETRY ERROR: ${e.message}');
    } on TimeoutException {
      debugPrint('DEVICE TELEMETRY TIMEOUT');
    } catch (e) {
      debugPrint('DEVICE TELEMETRY FAILED: $e');
    }
    return fallbackSnapshot();
  }

  /// The static part only (manufacturer, model, RAM, ...).
  Future<Map<String, Object?>> deviceInfo() async {
    final cached = _cachedDevice;
    if (cached != null && cached.isNotEmpty) return cached;

    final snap = await snapshot();
    final device = _asMap(snap['device']);
    if (device.isNotEmpty) {
      _cachedDevice = device;
      return device;
    }
    return fallbackDevice();
  }

  /// Used when the native channel is not available. Values are honest:
  /// we say "unknown" instead of inventing a phone model.
  Map<String, Object?> fallbackSnapshot() => {
        'device': fallbackDevice(),
      };

  Map<String, Object?> fallbackDevice() => {
        'manufacturer': 'unknown',
        'brand': 'unknown',
        'model': 'unknown',
        'device': 'unknown',
        'android_api': 0,
        'android_release': 'unknown',
        'cpu_abi': 'unknown',
        'cpu_cores': 0,
        'ram_total_mb': 0,
        'ram_class': 'unknown',
        'backend': backend,
        'platform': Platform.operatingSystem,
      };

  /// Turns whatever the platform sent into plain Map/List/primitive values so
  /// it can safely be passed to jsonEncode().
  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _normalize(item)));
    }
    return <String, Object?>{};
  }

  static Object? _normalize(Object? value) {
    if (value is Map) return _asMap(value);
    if (value is List) return value.map(_normalize).toList();
    return value;
  }
}

/// The contract-shaped "device envelope".
class DeviceEnvelope {
  DeviceEnvelope({
    required this.device,
    this.start,
    this.end,
    this.peakProcessPssMb,
  });

  final Map<String, Object?> device;
  final Map<String, Object?>? start;
  final Map<String, Object?>? end;
  final int? peakProcessPssMb;

  Map<String, Object?> toMetadata() {
    final startMemory = _map(start?['memory']);
    final endMemory = _map(end?['memory']);
    final startThermal = _map(start?['thermal']);
    final endThermal = _map(end?['thermal']);
    final battery = _map(start?['battery']);

    final memory = <String, Object?>{};
    if (startMemory.isNotEmpty) {
      memory['available_mb_at_start'] = startMemory['available_mb'];
      memory['total_mb'] = startMemory['total_mb'];
      memory['threshold_mb'] = startMemory['threshold_mb'];
      memory['low_memory_at_start'] = startMemory['low_memory'];
      memory['process_pss_mb_at_start'] = startMemory['process_pss_mb'];
    }
    if (peakProcessPssMb != null) {
      memory['peak_process_pss_mb'] = peakProcessPssMb;
    }
    if (endMemory.isNotEmpty) {
      memory['available_mb_at_end'] = endMemory['available_mb'];
      memory['process_pss_mb_at_end'] = endMemory['process_pss_mb'];
    }

    final thermal = <String, Object?>{};
    if (startThermal.isNotEmpty) {
      thermal['status_at_start'] = startThermal['status'];
      thermal['status_name_at_start'] = startThermal['status_name'];
      thermal['headroom_at_start'] = startThermal['headroom'];
    }
    if (endThermal.isNotEmpty) {
      thermal['status_at_end'] = endThermal['status'];
      thermal['status_name_at_end'] = endThermal['status_name'];
      thermal['headroom_at_end'] = endThermal['headroom'];
    }

    return {
      'device': device.isEmpty ? DeviceTelemetry().fallbackDevice() : device,
      if (memory.isNotEmpty) 'memory': memory,
      if (thermal.isNotEmpty) 'thermal': thermal,
      if (battery.isNotEmpty) 'battery': battery,
    };
  }

  static Map<String, Object?> _map(Object? value) => DeviceTelemetry._asMap(value);
}

/// Samples the device while one answer is being produced.
///
/// Why sample more than once? The peak is what matters: a phone can look fine
/// before an answer and run out of memory in the middle of generation.
class DeviceEnvelopeSampler {
  DeviceEnvelopeSampler(
    this._telemetry, {
    this.interval = const Duration(seconds: 2),
  });

  final DeviceTelemetry _telemetry;
  final Duration interval;

  Timer? _timer;
  Map<String, Object?>? _start;
  Map<String, Object?>? _end;
  int? _peakProcessPssMb;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _start = await _telemetry.snapshot();
    _observe(_start);
    _timer = Timer.periodic(interval, (_) => unawaited(_sample()));
  }

  Future<void> _sample() async {
    if (!_running) return;
    try {
      final snapshot = await _telemetry.snapshot();
      _observe(snapshot);
    } catch (_) {
      // A failed sample must never affect the answer.
    }
  }

  void _observe(Map<String, Object?>? snapshot) {
    final memory = DeviceTelemetry._asMap(snapshot?['memory']);
    final pss = _asInt(memory['process_pss_mb']);
    if (pss != null && (_peakProcessPssMb == null || pss > _peakProcessPssMb!)) {
      _peakProcessPssMb = pss;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    try {
      _end = await _telemetry.snapshot();
      _observe(_end);
    } catch (_) {}
  }

  /// Always safe to call: it stops the timer and returns the metadata object.
  Future<Map<String, Object?>> metadata() async {
    await stop();
    final device = DeviceTelemetry._asMap(_start?['device']);
    return DeviceEnvelope(
      device: device.isEmpty ? await _telemetry.deviceInfo() : device,
      start: _start,
      end: _end,
      peakProcessPssMb: _peakProcessPssMb,
    ).toMetadata();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
