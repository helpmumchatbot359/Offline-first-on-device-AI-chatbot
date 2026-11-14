# Diagnostic logs: adding device/runtime metrics

This guide is written for a complete beginner. It explains **what was added**,
**why**, and **how to check it on a real phone**.

---

## 1. The problem in one picture

There are two different uploads in this app:

```
Telemetry events  -> POST /v1/telemetry           (already had device info)
Diagnostic logs   -> POST /v1/diagnostic-logs     (did NOT have device info)
```

The diagnostic log file already looked like this:

```json
{
  "logId": "log-...",
  "offlineCycleId": "cycle-...",
  "timestamp": "2026-11-03T10:00:00.000Z",
  "logType": "inference_measurement",
  "networkState": "no_internet",
  "metrics": {
    "latency_ms": 152000,
    "success": true
  }
}
```

The backend asked for the `metrics` object to also say **which phone** ran the
answer and **how healthy it was**:

```json
"metrics": {
  "device": {
    "manufacturer": "Samsung",
    "model": "SM-A546B",
    "ram_total_mb": 8192,
    "ram_class": "8GB",
    "cpu_abi": "arm64-v8a",
    "cpu_cores": 8,
    "backend": "cpu"
  },
  "memory": {
    "available_mb_at_start": 1079,
    "process_pss_mb_at_start": 1200,
    "peak_process_pss_mb": 1442
  },
  "thermal": {
    "status_at_start": 2,
    "status_name_at_start": "moderate",
    "headroom_at_start": 0.4
  },
  "battery": {
    "percent": 80,
    "temperature_c": 31.5,
    "charging": false
  },
  "model_load_ms": 3912,
  "latency_ms": 152000,
  "success": true
}
```

---

## 2. Where the numbers come from

Nothing is guessed. The values come from Android through the existing channel:

```
Android OS
   │
   ▼
DeviceTelemetry.java
   ├── Build.*                  -> manufacturer, model, Android version
   ├── ActivityManager          -> total RAM, available RAM
   ├── Debug.getMemoryInfo()    -> process PSS (memory this app uses)
   ├── PowerManager             -> thermal status / headroom
   └── BatteryManager           -> battery percent, temperature, charging
   │
   ▼
MethodChannel "mama_ai/device_info"
   │
   ▼
DeviceTelemetry.snapshot()  ->  { device, memory, thermal, battery }
```

`backend` is passed from Dart (`cpu` today). If the app later uses a GPU/NPU,
change that one value in `main.dart`.

---

## 3. Step-by-step code changes

### Step 1 — Let `DiagnosticLogger` read the phone

File: `lib/features/chat/data/local/diagnostic_logger.dart`

At the top, import the existing device reader:

```dart
import '../telemetry/device_telemetry.dart';
```

Give the logger a `DeviceTelemetry` object. If nobody passes one, it creates its
own, so the logger can never be "forgotten":

```dart
class DiagnosticLogger {
  DiagnosticLogger({DeviceTelemetry? deviceTelemetry})
      : _deviceTelemetry = deviceTelemetry ?? DeviceTelemetry();

  final DeviceTelemetry _deviceTelemetry;
```

### Step 2 — Build the same envelope telemetry already uses

Still in `diagnostic_logger.dart`, `withRuntimeDiagnostics()`:

1. takes one live snapshot (`{ device, memory, thermal, battery }`);
2. passes it to `DeviceEnvelope(...).toMetadata()`;
3. adds the raw numbers as well (`available_mb`, `process_pss_mb`);
4. merges the caller's own metrics on top.

The key rule:

> If the caller measured a whole inference (start, peak, end), the caller wins.
> Those values describe the answer that just ran; a snapshot taken later does not.

That is why the merge is **deep**: a caller `memory` map cannot wipe out the
`device` block or the battery block.

### Step 3 — Enrich every record before writing it

`logEvent()` now does:

```dart
final enrichedMetrics = await withRuntimeDiagnostics(metrics);
...
'metrics': enrichedMetrics,
```

Because this happens inside the one method that writes every line, **every**
diagnostic record gets the block: cycle started, cycle ended, sync measurement,
sync error, inference measurement, etc.

There is a second safety net in `readPending()`: files written by an older app
version may have no device block. Right before upload, the logger takes **one**
snapshot and adds it to every record in that batch. So even old queued logs reach
the table with the runtime facts.

### Step 4 — Give the logger the shared device reader in `main.dart`

File: `lib/main.dart`

The device reader is now created **before** the diagnostics logger:

```dart
final deviceTelemetry = DeviceTelemetry(backend: 'cpu');
final diagnosticLogger = DiagnosticLogger(deviceTelemetry: deviceTelemetry);
```

Sharing one reader means telemetry and diagnostics always report the same phone.

### Step 5 — Pass the measured per-answer values

File: `lib/features/chat/data/chat_repository_impl.dart`

The chat repository already ran a `DeviceEnvelopeSampler` during the answer.
At the end of the request it now writes:

```dart
final runtimeDiagnostics = offlineAttempted
    ? await run.envelope.metadata()
    : const <String, Object?>{};

diagnosticLogger.logEvent(
  logType: 'inference_measurement',
  metrics: {
    'latency_ms': overall.elapsedMilliseconds,
    'success': success,
    if (run.modelLoadMs != null) 'model_load_ms': run.modelLoadMs,
    ...runtimeDiagnostics,
  },
);
```

`run.envelope.metadata()` contains:

| Field | Meaning |
| --- | --- |
| `memory.available_mb_at_start` | free phone memory before the model loaded |
| `memory.process_pss_mb_at_start` | memory this app used at the start |
| `memory.peak_process_pss_mb` | **highest** PSS seen while the answer ran |
| `thermal.status_at_start` / `..._at_end` | how hot the phone was |
| `battery.*` | percent, temperature, charging |
| `device.*` | model, RAM, CPU/ABI, backend |

`model_load_ms` is copied from `run.modelLoadMs`, which is set immediately after
the 2.5 GB model finishes initializing.

If the answer came from the cloud only, no sampler data exists; the logger still
adds a live `device` / `memory` / `thermal` / `battery` snapshot.

---

## 4. What the server receives

`SyncService._syncPendingDiagnostics()` sends the records without changing
`metrics`:

```json
{
  "offline_cycle_id": "cycle-...",
  "records": [
    {
      "log_id": "log-...",
      "timestamp": "2026-11-03T10:00:00.000Z",
      "log_type": "inference_measurement",
      "network_state": "no_internet",
      "metrics": {
        "latency_ms": 152000,
        "success": true,
        "model_load_ms": 3912,
        "device": {
          "manufacturer": "Samsung",
          "model": "SM-A546B",
          "ram_total_mb": 8192,
          "ram_class": "8GB",
          "cpu_abi": "arm64-v8a",
          "cpu_cores": 8,
          "backend": "cpu"
        },
        "memory": {
          "available_mb": 1079,
          "available_mb_at_start": 1079,
          "process_pss_mb": 1200,
          "process_pss_mb_at_start": 1200,
          "peak_process_pss_mb": 1442
        },
        "thermal": {
          "status": 2,
          "status_name": "moderate",
          "headroom": 0.4,
          "status_at_start": 2,
          "status_name_at_start": "moderate"
        },
        "battery": {
          "percent": 80,
          "temperature_c": 31.5,
          "charging": false,
          "plugged": false
        }
      }
    }
  ]
}
```

The backend's "diagnostics table" can therefore answer:

| Question | Column inside `metrics` |
| --- | --- |
| Which phone? | `device.manufacturer`, `device.model` |
| How much RAM? | `device.ram_total_mb`, `device.ram_class` |
| Free memory? | `memory.available_mb_at_start` |
| App memory? | `memory.process_pss_mb_at_start`, `memory.peak_process_pss_mb` |
| Model load time? | `model_load_ms` |
| Heat? | `thermal.status_name_at_start`, `thermal.status_name_at_end` |
| Battery? | `battery.percent`, `battery.temperature_c`, `battery.charging` |
| CPU/backend? | `device.cpu_abi`, `device.cpu_cores`, `device.backend` |

---

## 5. How to check it on a phone (beginner steps)

1. Connect the Android phone with USB debugging on.
2. Open a terminal in the project folder and run:

   ```powershell
   flutter run
   ```

3. In the app, turn off Wi-Fi and mobile data (airplane mode is fine after the
   app is running) so the on-phone model answers.
4. Ask one question and wait for the answer.
5. Open a second terminal and find the log files:

   ```powershell
   adb shell run-as com.helpmum.mamaBot ls app_flutter/diagnostic_logs
   ```

6. Print the newest file:

   ```powershell
   adb shell run-as com.helpmum.mamaBot cat app_flutter/diagnostic_logs/diagnostics-2026-11-03.jsonl
   ```

7. Look for a line whose `logType` is `inference_measurement`. Its `metrics`
   must contain `device`, `memory`, `thermal`, `battery` and `model_load_ms`.

8. Reconnect to the internet and wait for a sync. Confirm on the backend that
   the row inserted into the diagnostics table has the same values.

### Run the automated checks

```powershell
flutter test test/diagnostic_logger_metrics_test.dart
flutter test test/telemetry_tool_alignment_test.dart
flutter analyze
```

---

## 6. Troubleshooting

### `device.model` is `"unknown"`

The native channel was not available (desktop/test build) or the Android method
channel is not registered. On a real phone, rebuild the app after changing Java.

### `memory.peak_process_pss_mb` equals the start value

The answer was very short, or the sampler never saw a higher value. The peak is
still honest: it is the highest value actually observed.

### `model_load_ms` is missing

That record was not an on-phone model answer (for example a cloud-only answer),
or model loading failed before the value was set. It is never invented.

### Old `.sent` files

After a successful upload, `markUploaded()` renames a file to
`diagnostics-....jsonl.sent`. Those are already synced and are ignored by
`readPending()`.

### The logs look empty

`DiagnosticLogger.logEvent()` deliberately swallows write errors: diagnostics
must never crash the chat. Check that the app has storage permission-free access
to its own documents directory (`app_flutter`).
