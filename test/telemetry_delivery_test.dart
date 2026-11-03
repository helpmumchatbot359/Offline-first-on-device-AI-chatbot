// Tests that an offline answer REALLY becomes a stored telemetry event.
//
// Why this file exists:
//   A diagnostic record and a telemetry record are built in different places.
//   It is possible for the diagnostics table to show an inference while the
//   telemetry table has zero rows. These tests protect the telemetry side:
//
//     1. a successful offline answer is stored as offline_inference;
//     2. null fields are removed (strict servers reject them);
//     3. even if the device snapshot breaks, the event is still stored.
//
// Run with: flutter test test/telemetry_delivery_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/local/chat_local_data_source.dart';
import 'package:mama_ai/features/chat/data/local/entities/local_telemetry_entity.dart';
import 'package:mama_ai/features/chat/data/sync/sync_service.dart';
import 'package:mama_ai/features/chat/data/telemetry/device_telemetry.dart';
import 'package:mama_ai/features/chat/data/telemetry/telemetry_recorder.dart';

/// Captures events instead of writing to ObjectBox, so the test has no database.
class CapturingLocalDataSource extends ChatLocalDataSource {
  final List<LocalTelemetryEvent> saved = [];

  @override
  Future<void> saveTelemetryEvent(LocalTelemetryEvent event) async {
    saved.add(event);
  }
}

class FakeDeviceTelemetry extends DeviceTelemetry {
  @override
  Future<Map<String, Object?>> snapshot() async => {
        'device': {
          'manufacturer': 'Samsung',
          'model': 'SM-A546B',
          'ram_total_mb': 8192,
          'ram_class': '8GB',
          'cpu_abi': 'arm64-v8a',
          'cpu_cores': 8,
          'backend': 'cpu',
        },
        'memory': {
          'available_mb': 1079,
          'total_mb': 8192,
          'process_pss_mb': 1200,
        },
        'thermal': {'status': 2, 'status_name': 'moderate'},
        'battery': {'percent': 80, 'temperature_c': 31.5, 'charging': false},
      };
}

/// Simulates a native channel that is completely broken.
class BrokenDeviceTelemetry extends DeviceTelemetry {
  @override
  Future<Map<String, Object?>> snapshot() async => throw StateError('native channel down');

  @override
  Map<String, Object?> fallbackSnapshot() => throw StateError('fallback also down');
}

bool hasNull(Object? value) {
  if (value == null) return true;
  if (value is Map) return value.values.any(hasNull);
  if (value is List) return value.any(hasNull);
  return false;
}

void main() {
  test('successful offline answer is stored as offline_inference', () async {
    final local = CapturingLocalDataSource();
    final recorder = TelemetryRecorder(local, deviceTelemetry: FakeDeviceTelemetry());

    await recorder.recordOfflineInference(
      chatId: 'user-lily',
      modelVersion: TelemetryContract.modelVersion,
      latencyMs: 12000,
      outcome: 'success',
      // null values mimic what the real response builder can produce.
      responseMetadata: {
        'tool_used': false,
        'retrieved_passage_count': 0,
        'streamed': true,
        'model_load_ms': 3900,
        'time_to_first_token_from_request_ms': null,
        'stream_duration_ms': null,
        'generation_duration_ms': 8100,
      },
    );

    expect(local.saved, hasLength(1));
    final event = local.saved.single;
    expect(event.eventType, TelemetryContract.offlineInference);
    expect(event.chatId, 'user-lily');
    expect(event.latencyMs, 12000);
    expect(event.outcome, 'success');
    expect(TelemetryContract.validate(event), isEmpty);

    final meta = jsonDecode(event.metadataJson) as Map<String, dynamic>;
    expect(meta.containsKey('error_stage'), isFalse, reason: 'null must not be sent on success');
    expect(meta.containsKey('time_to_first_token_from_request_ms'), isFalse);
    expect(meta.containsKey('stream_duration_ms'), isFalse);
    expect(hasNull(meta), isFalse);
    expect((meta['device'] as Map)['model'], 'SM-A546B');
    expect(meta['retrieved_passage_count'], 0);
  });

  test('a broken device snapshot never loses the telemetry event', () async {
    final local = CapturingLocalDataSource();
    final recorder = TelemetryRecorder(local, deviceTelemetry: BrokenDeviceTelemetry());

    await recorder.recordOfflineInference(
      chatId: 'user-lily',
      modelVersion: TelemetryContract.modelVersion,
      latencyMs: 9000,
      outcome: 'success',
      responseMetadata: {
        'tool_used': false,
        'retrieved_passage_count': 0,
        'streamed': true,
      },
    );

    expect(local.saved, hasLength(1));
    expect(TelemetryContract.validate(local.saved.single), isEmpty);
  });

  test('withoutNulls removes nulls at every level but keeps false and 0', () {
    final cleaned = TelemetryRecorder.withoutNulls({
      'a': null,
      'b': {'c': null, 'd': 1},
      'e': [null, 2],
      'f': false,
      'g': 0,
    });

    expect(cleaned.containsKey('a'), isFalse);
    expect(cleaned['b'], {'d': 1});
    expect(cleaned['e'], [2]);
    expect(cleaned['f'], isFalse);
    expect(cleaned['g'], 0);
  });

  test('upload payload never sends optional null fields', () {
    final event = LocalTelemetryEvent(
      eventUuid: 'event-lily',
      eventType: TelemetryContract.offlineInference,
      chatId: 'user-lily',
      date: '2026-11-03T10:00:00.000Z',
      modelVersion: TelemetryContract.modelVersion,
      latencyMs: 12000,
      outcome: 'success',
      errorCode: null,
      connectivity: 'offline',
      metadataJson: jsonEncode({
        'tool_used': false,
        'retrieved_passage_count': 0,
        'error_stage': null,
        'memory': {'available_mb_at_start': 1079, 'peak_process_pss_mb': null},
      }),
      syncState: 'pending',
    );

    final payload = SyncService.buildTelemetryPayload(event);

    expect(payload.containsKey('error_code'), isFalse);
    expect(payload['latency_ms'], 12000);
    expect(payload['chat_id'], 'user-lily');

    final metadata = payload['metadata'] as Map;
    expect(metadata.containsKey('error_stage'), isFalse);
    expect((metadata['memory'] as Map).containsKey('peak_process_pss_mb'), isFalse);
    expect((metadata['memory'] as Map)['available_mb_at_start'], 1079);
  });
}
