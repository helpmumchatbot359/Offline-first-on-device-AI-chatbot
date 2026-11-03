# Telemetry: device envelope + retrieval metadata

This document explains, step by step, what was added and **why**. It assumes
you are new to Flutter/Android telemetry.

> Diagnostic logs (`POST /v1/diagnostic-logs`) use the same envelope too. See
> [`DIAGNOSTIC_LOG_METRICS.md`](./DIAGNOSTIC_LOG_METRICS.md) for that path.

---

## 1. What the backend wanted

Every telemetry event now has to answer three questions:

1. **Which phone was this?** (manufacturer, model, Android version, RAM class)
2. **Was the phone healthy while it worked?** (free memory, peak memory, heat,
   battery)
3. **Did the AI use retrieval, and how many passages came back?**

The target shape of `metadata` is:

```json
{
  "device": {
    "manufacturer": "Samsung",
    "brand": "samsung",
    "model": "SM-A546B",
    "device": "a54x",
    "android_api": 35,
    "android_release": "15",
    "cpu_abi": "arm64-v8a",
    "cpu_cores": 8,
    "ram_total_mb": 8192,
    "ram_class": "8GB",
    "backend": "cpu",
    "app_version": "1.0.0"
  },
  "memory": {
    "available_mb": 5340,
    "total_mb": 8192,
    "threshold_mb": 200,
    "low_memory": false,
    "process_pss_mb": 2860,
    "available_mb_at_start": 5340,
    "process_pss_mb_at_start": 1200,
    "peak_process_pss_mb": 2860,
    "available_mb_at_end": 4000,
    "process_pss_mb_at_end": 2500
  },
  "thermal": {
    "status_at_start": 2,
    "status_name_at_start": "moderate",
    "headroom_at_start": 0.4,
    "status_at_end": 3,
    "status_name_at_end": "severe",
    "headroom_at_end": 0.2
  },
  "battery": {
    "percent": 80,
    "temperature_c": 31.5,
    "charging": false,
    "plugged": false
  },
  "tool_used": true,
  "retrieved_passage_count": 2,
  "output_tokens": 128,
  "output_chars": 512,
  "streamed": true,
  "model_load_ms": 8400,
  "time_to_first_token_ms": 119000,
  "time_to_first_token_from_request_ms": 127400,
  "stream_duration_ms": 8600,
  "generation_duration_ms": 127600,
  "tokens_per_second": 4.1
}
```

`latency_ms` on the event itself stays the **whole on-phone request time**.
The extra timing fields let you split that time into:

| Field | Meaning |
| --- | --- |
| `model_load_ms` | time spent loading the 2.5 GB model |
| `time_to_first_token_ms` | time from "generation started" to the first word |
| `time_to_first_token_from_request_ms` | same, counted from the start of the whole request |
| `stream_duration_ms` | time between the first word and the last word |
| `generation_duration_ms` | whole generation phase (model already loaded) |

---

## 2. The flow, from the phone to the server

```
Android OS
   │  DeviceTelemetry.java  (reads Build.*, ActivityManager, Debug, PowerManager, BatteryManager)
   ▼
MethodChannel "mama_ai/device_info"  ->  snapshot()
   │
   ▼
DeviceTelemetry.dart  ->  one Map { device, memory, thermal, battery }
   │
   ├── TelemetryRecorder._save()          adds the device envelope to EVERY event
   │
   └── DeviceEnvelopeSampler               samples during one AI answer
            │  start()  -> values at the beginning
            │  every 2s -> keeps the peak process PSS
            │  stop()   -> values at the end
            ▼
        OfflineRun.fullResponseMetadata()
            │  tool_used, retrieved_passage_count, timings, memory, thermal...
            ▼
        TelemetryRecorder.recordOfflineInference()
            │
            ▼
        Local ObjectBox queue ("pending")
            │
            ▼
        SyncService -> POST /v1/telemetry
```

Key rule from the old code: **there is exactly ONE place that creates
telemetry events** — `TelemetryRecorder._save()`. That is why the device
envelope is added there: it is impossible to forget it on a new event type.

---

## 3. Files that changed

### New: `android/.../DeviceTelemetry.java`

Reads the native values:

- `Build.MANUFACTURER`, `Build.MODEL`, `Build.VERSION.SDK_INT`, ...
- `ActivityManager.MemoryInfo` → available memory, total memory, low-memory flag
- `Debug.getMemoryInfo()` → real process **PSS** in MB
- `PowerManager.getCurrentThermalStatus()` / `getThermalHeadroom()` → throttling
- `BatteryManager` sticky intent → percent, temperature, charging
- `ram_class` is derived from total RAM (phones report 7,600 MB for an 8 GB phone,
  so it rounds to the class users recognise)

Every read is wrapped in `try/catch`: a missing number must never crash the app.

### New: `lib/.../telemetry/device_telemetry.dart`

Three small classes:

- `DeviceTelemetry` — talks to the native channel, with a 900 ms timeout and an
  honest fallback (`"unknown"`) when the channel does not exist (unit tests).
- `DeviceEnvelope` — converts start/end snapshots into the exact metadata shape.
- `DeviceEnvelopeSampler` — takes one snapshot at the start, samples every
  **2 seconds**, keeps the **highest** PSS, and takes one snapshot at the end.

> Why sample? A phone can look healthy before an answer and run out of memory
> halfway through. The peak is the number that explains a crash.

### Changed: `MainActivity.java`

Registers `MethodChannel("mama_ai/device_info")` with one method, `snapshot`.
Dart passes the backend name (`cpu`) and gets a normal Map back.

### Changed: `telemetry_recorder.dart`

- `_save()` now calls `_withDeviceEnvelope()` before storing the event.
- The caller's metadata wins over the live snapshot. That is how the
  per-inference memory (start/peak/end) is preserved.
- `recordRuntimeFailure()` accepts `extraMetadata` so a failure also carries the
  memory/thermal envelope measured during the failed run.
- The validator now requires `offline_inference.metadata.retrieved_passage_count`
  to be a whole number ≥ 0 and checks the new timing fields.

### Changed: `chat_repository_impl.dart`

- `OfflineRun` owns a `DeviceEnvelopeSampler`.
- The sampler starts before the model is loaded and stops in `finally`, so it
  covers model load + generation + cancellation.
- `model_load_ms` is recorded right after `ensureInitialized()`.
- Timings are now measured from the **start of generation**, not from the start
  of the whole request, so `time_to_first_token_ms` means what its name says.
- `responseMetadata()` ALWAYS includes `retrieved_passage_count`
  (`0` when no passage was retrieved), plus `output_chars`,
  `stream_duration_ms` and `generation_duration_ms`.

### Changed: `OfflineMamaAiRuntime.java` (the Java source values you mentioned)

The runtime already had `toolWasUsed` and `passages.size()`. It now actually
sends them:

- `completed` → `tool_used`, `tool_error`, `retrieved_passage_count`,
  `output_tokens`, `streamed`
- `tool_result` → `tool_used`, `retrieved_passage_count`, `tool_error`
- `retrieval_context` → `retrieved_passage_count`, `tool_used`
- `cancelled` → same facts + `error_code: "CANCELLED"`
- `error` → same facts + `error_code` (`TOOL_ERROR`, `GENERATION_TIMEOUT`) and a
  contract-shaped `error_stage` (`tool_execution`, `retrieval`, `context_build`,
  `generation`)

`containsToolError()` checks the tool result objects (`{"result":{"error":...}}`)
so the phone knows a tool **really failed**, instead of guessing from text.

### Changed: `main.dart`

Creates one `DeviceTelemetry(backend: 'cpu')` and gives it to the
`TelemetryRecorder`.

### Changed: `diagnostic_logger.dart`

Every diagnostic record is now enriched with the same `device`, `memory`,
`thermal` and `battery` blocks. `inference_measurement` also carries
`model_load_ms` and the sampler's start/peak/end values. Details:
[`DIAGNOSTIC_LOG_METRICS.md`](./DIAGNOSTIC_LOG_METRICS.md).

---

## 4. Why retrieval can now trigger RAG analysis

Before, the backend could not tell a retrieval answer from a normal answer:

- `tool_used` was never sent by Java
- `retrieved_passage_count` was missing

Now both are present on every `offline_inference` event:

- `tool_used: false`, `retrieved_passage_count: 0` → pure model answer
- `tool_used: true`, `retrieved_passage_count: 0` → retrieval ran, found nothing
- `tool_used: true`, `retrieved_passage_count: 2` → grounded answer

That last case is what RAG analysis needs.

---

## 5. How to test it on a phone

1. Connect an Android device and run the app:
   ```powershell
   flutter run
   ```
2. Ask one question that needs the knowledge base (so the retrieval tool runs).
3. In the debug console, look for:
   ```
   TELEMETRY SAVED offline_inference outcome=success code=null metadata={...}
   ```
4. Check that `metadata.device.model` is your phone and
   `metadata.retrieved_passage_count` is a number.
5. Make the answer fail (tap Stop, or use a device with little RAM) and confirm
   the event still contains `device`, `memory`, `thermal` and `battery`.

Run the automated checks:

```powershell
flutter test test/telemetry_tool_alignment_test.dart
flutter analyze
```

---

## 6. Practical notes

- **No new database columns.** Everything lives inside the existing
  `metadataJson`, so ObjectBox does not need regeneration.
- **Privacy.** The envelope contains hardware facts only. Message text, prompts
  and AI answers are still forbidden by `TelemetryContract._forbiddenMetadataKeys`.
- **No permissions needed.** RAM, PSS, thermal status and battery temperature are
  readable without runtime permissions.
- **Old queued events** without a device block are still accepted by the
  validator. Only new events are enriched. If you want to force the rule for
  old data too, add `metadata.device` to the required checks in
  `TelemetryContract.validate()`.
- **Backend choice.** `main.dart` sends `backend: 'cpu'`. If you switch the
  native runtime to GPU/NPU, change that one value (or pass the real backend
  from `OfflineAiBridge.initialize`).

---

## 7. Troubleshooting

### “The log stops in the middle of a word”

That is **logcat/terminal truncation**, not missing data. A single log line is
cut at roughly a few thousand characters. The event stored in ObjectBox is
complete.

To make this obvious, `TelemetryRecorder` now prints:

```
TELEMETRY SAVED offline_inference ... metadata_length=1520
TELEMETRY META[1] {"device":{...},"memory":...
TELEMETRY META[2] ...continuation...
TELEMETRY META[3] ...continuation...
```

If you still only see META[1], the terminal itself is hiding the later lines;
scroll the console or use Android Studio's logcat search for `TELEMETRY META`.

### Numbers look like `31.0` instead of `31`

Fixed in `MainActivity.toFlutterValue()`: integers are now sent as integers.
Gson's default `fromJson(..., Object.class)` was turning every number into a
`double`.

### A phone with 4 GB RAM reports `ram_total_mb: 3779`

That is normal. Android reserves memory for the OS, so `MemoryInfo.totalMem` is
smaller than the marketing “4 GB”. `ram_class` rounds it to `"4GB"` on purpose.

