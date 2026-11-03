# Why offline inference telemetry was missing (and what changed)

This guide is for a beginner. Read it top to bottom; each step explains one
small idea.

---

## 1. The symptom

For the same Lily chat/session:

| Place | Result |
| --- | --- |
| Chat sync (`/v1/chats/sync`) | ✅ present in `UserChat` |
| Diagnostic logs (`/v1/diagnostic-logs`) | ✅ 14 rows, including 8–17 s offline answers |
| Inference telemetry (`/v1/telemetry`) | ❌ **0 rows** |

That combination is important:

- The phone **did** answer offline (diagnostics prove it).
- The network **did** work after reconnecting (chat and diagnostics synced).
- So the problem is **not** "offline AI did not run".
- The problem is in the **telemetry event pipeline**: creation, storage, or upload.

---

## 2. The two pipelines are separate

Think of two envelopes leaving the phone:

```
Offline answer
   │
   ├── Envelope A: diagnostic logs
   │      POST /v1/diagnostic-logs
   │      "A measurement happened: 12 seconds, success."
   │      (works even if telemetry is broken)
   │
   └── Envelope B: telemetry
          POST /v1/telemetry
          "An offline_inference event happened for chat user-Lily."
          (this is the one that was missing)
```

Diagnostics are a **measurement** of what happened.
Telemetry is the **contract event** the backend uses for inference analytics.

They are uploaded by different code paths, so one can succeed while the other
fails.

---

## 3. The important rule: one bad event can block a batch

Telemetry is sent in batches (up to 50 events in one HTTP request).

Before this fix:

```text
Phone queue: [offline_started, offline_inference, sync_error, ...]
                         │
                         ▼
             POST /v1/telemetry  (all at once)
                         │
                  server says 400
                         │
                         ▼
          NOTHING in that batch is marked uploaded
```

If the server refuses the whole batch because of **one field in one event**,
every good `offline_inference` behind it sits in the queue forever.

Diagnostics are not part of that batch, so they still arrive. That is exactly
the pattern you saw.

---

## 4. The likely bad fields: `null`

The old payload sent optional fields even when they had no value.

Example: a **successful** answer has no error, so the old app sent:

```json
{
  "event_uuid": "event-...",
  "event_type": "offline_inference",
  "chat_id": "user-...",
  "date": "2026-11-03T10:00:00.000Z",
  "model_version": "gemma-4-e2b-mobile",
  "latency_ms": 12000,
  "outcome": "success",
  "error_code": null,
  "connectivity": "offline",
  "metadata": {
    "error_stage": null,
    "tool_used": false,
    "retrieved_passage_count": 0,
    "streamed": true
  }
}
```

Many strict JSON validators accept a **missing** field, but reject a field whose
value is `null`. The contract example for `offline_started` does not contain
`latency_ms`, `outcome` or `error_code` at all.

So the fix is:

> **Never send a key that has no value. Omit it completely.**

---

## 5. What was changed (step by step)

### Step 1 — Remove nulls from metadata before storing

File: `lib/features/chat/data/telemetry/telemetry_recorder.dart`

New helper:

```dart
static Map<String, Object?> withoutNulls(Map<String, Object?> value)
```

It walks the whole map and removes:

- top-level nulls (`"error_stage": null`)
- nested nulls (`"memory": {"peak_process_pss_mb": null}`)
- nulls inside lists

It keeps real values like `false` and `0`, because those are **not** missing.

`_save()` now calls it before `jsonEncode(...)`:

```dart
enrichedMetadata = withoutNulls(enrichedMetadata);
```

### Step 2 — Do not send `error_stage` on a successful answer

File: `telemetry_recorder.dart`

Before:

```dart
metadata: {
  'error_stage': errorStage, // null on success
  ...responseMetadata,
}
```

After:

```dart
metadata: {
  'error_stage': ?errorStage, // omitted when null
  ...responseMetadata,
}
```

### Step 3 — Omit optional null fields from the HTTP payload too

File: `lib/features/chat/data/sync/sync_service.dart`

The payload builder now adds a field only when it has a value:

```dart
if (e.chatId != null && e.chatId!.isNotEmpty) payload['chat_id'] = e.chatId;
if (e.modelVersion != null) payload['model_version'] = e.modelVersion;
if (e.latencyMs != null) payload['latency_ms'] = e.latencyMs;
if (e.outcome != null) payload['outcome'] = e.outcome;
if (e.errorCode != null) payload['error_code'] = e.errorCode;
```

It also cleans metadata from **old queued events** at upload time, so an event
written by an older app version is fixed before it leaves the phone.

### Step 4 — One bad event can no longer block the batch

Still in `sync_service.dart`, `_postTelemetry()` now reports:

- `ok` — server accepted **and acknowledged every UUID**.
- `permanent` — server returned 400/413/422, meaning the payload itself is bad.
- `status` — HTTP status.
- `body` — server response (used in diagnostics).
- `acknowledged` — UUIDs the server confirmed.

If a batch fails with a permanent error, the app **retries each event on its
own**:

```text
batch 400
   ├── event 1 alone -> 200 + ack  -> marked uploaded
   ├── event 2 alone -> 400        -> quarantined + diagnostic record
   └── event 3 alone -> 200 + ack  -> marked uploaded
```

Good events now get through even when one event is bad.

### Step 5 — Quarantine refused events instead of blocking forever

File: `lib/features/chat/data/local/chat_local_data_source.dart`

New method:

```dart
Future<void> markTelemetryRejected(List<int> localIds)
```

A permanently refused event gets `syncState = 'rejected'`.

`'rejected'` is **not** `'pending'`, so it stops blocking newer events. The
event is kept on the phone for debugging; it is not silently deleted.

### Step 6 — Never lose the event when the device snapshot breaks

File: `telemetry_recorder.dart` and `chat_repository_impl.dart`

If building the device envelope throws, the event is still saved with its core
measurements:

```dart
try {
  enrichedMetadata = await _withDeviceEnvelope(metadata);
} catch (e) {
  enrichedMetadata = {...metadata}; // no device block, but event survives
}
```

And if `fullResponseMetadata()` fails:

```dart
try {
  responseMetadata = await run.fullResponseMetadata();
} catch (e) {
  responseMetadata = run.responseMetadata();
}
```

### Step 7 — Add an audit trail in diagnostics

Every telemetry event now writes a small diagnostic record:

| `log_type` | Meaning |
| --- | --- |
| `telemetry_event_saved` | Event really reached the phone's local queue |
| `telemetry_event_rejected` | Local validator refused the event |
| `telemetry_event_failed` | An exception happened while saving |
| `telemetry_upload_not_acknowledged` | Server replied 2xx but did not confirm all UUIDs |
| `telemetry_event_rejected_by_server` | Server permanently refused one event (includes response) |
| `telemetry_dropped_invalid` | Old invalid event removed before upload |

This lets you tell **exactly** where the event stopped:

```text
No telemetry_event_saved          -> event was never created
telemetry_event_saved, no upload  -> event is waiting on the phone
rejected_by_server                -> server refused it (reason is in the log)
saved + acknowledged              -> it reached the telemetry table
```

---

## 6. How to verify on the phone (beginner steps)

1. Rebuild and run the app:

   ```powershell
   flutter run
   ```

2. Turn on airplane mode.
3. Ask one question and wait for the offline answer.
4. Turn the internet back on and wait 10–20 seconds.
5. Read the diagnostic log:

   ```powershell
   adb shell run-as com.example.mama_ai ls app_flutter/diagnostic_logs
   adb shell run-as com.example.mama_ai cat app_flutter/diagnostic_logs/diagnostics-2026-11-03.jsonl
   ```

6. Search for `telemetry_event_saved`. You want a line like:

   ```json
   {
     "log_type": "telemetry_event_saved",
     "metrics": {
       "event_uuid": "event-...",
       "event_type": "offline_inference",
       "chat_id": "user-...",
       "outcome": "success",
       "latency_ms": 12000
     }
   }
   ```

7. If instead you see `telemetry_event_rejected_by_server`, the server's reason
   is in `metrics.server_response`. Fix that field or send the log to the backend
   engineer.

8. Check the backend telemetry table for that `event_uuid`.

---

## 7. What about the old missing events?

- If an old event is still **pending** on the phone, the new upload code will
  sanitize it and try again. It may now reach the table.
- If the old code already **dropped** it, it is gone from the phone and cannot be
  recovered.
- New answers after this build will be traceable from the moment they are saved.

---

## 8. Run the tests

```powershell
flutter test test/telemetry_delivery_test.dart
flutter test test/telemetry_tool_alignment_test.dart
flutter test test/diagnostic_logger_metrics_test.dart
flutter analyze
```

`telemetry_delivery_test.dart` proves:

1. a successful offline answer becomes an `offline_inference` event;
2. null fields are removed;
3. a broken device snapshot does not lose the event;
4. the upload payload does not contain optional nulls.

---

## 9. Second cause found: the upload was never triggered

Creating the event is only half the job. Something must call
`SyncService.syncAll()` to carry it to the server.

Before this second change, `syncAll()` ran at only two moments:

1. when the app started (`startBackgroundSync()`), and
2. when Android reported a **connectivity change** (`none` -> `wifi`).

That is fragile:

- If the app was in the background when you turned Wi-Fi back on, the change
  could be missed or the Dart isolate could be paused.
- `syncAll()` re-checks the network with `checkConnectivity()`. One second
  after reconnecting, that call can still return `none`. `syncAll()` then
  returns immediately — and nothing ever tries again.
- A phone that is never fully restarted can keep the event forever.

That matches the symptom "the event exists but never reaches the backend".

### Fix A — a 60-second heartbeat

`sync_service.dart` now starts a timer:

```dart
static const _heartbeatInterval = Duration(seconds: 60);
_heartbeat ??= Timer.periodic(_heartbeatInterval, (_) => unawaited(syncAll()));
```

`syncAll()` does nothing when the queues are empty, so this is cheap. It makes
upload independent of connectivity events.

### Fix B — upload immediately when an event is created

`telemetry_recorder.dart` now has a hook:

```dart
void Function()? onEventQueued;
```

`main.dart` connects it to the sync service:

```dart
telemetry.onEventQueued = syncService.syncAll;
```

So the moment an `offline_inference` is stored, the app tries to upload it. If
there is no network, `syncAll()` returns quietly and the heartbeat retries.

### Fix C — the phone now reports its own queue to the backend

Because **diagnostics upload successfully**, they are used as the debug channel.
Every sync writes:

```json
{ "log_type": "telemetry_queue_state",
  "metrics": { "pending_events": 1, "rejected_events": 0, "telemetry_sync_ok": true } }
```

and every successful telemetry upload writes:

```json
{ "log_type": "telemetry_upload_acknowledged",
  "metrics": { "batch_size": 1, "event_types": ["offline_inference"],
               "first_event_uuid": "event-...", "first_chat_id": "user-..." } }
```

How to read them:

| What you see in the diagnostics table | Meaning |
| --- | --- |
| `telemetry_event_saved` | Event created on the phone |
| `telemetry_queue_state.pending_events > 0` | Still waiting to upload |
| `telemetry_upload_acknowledged` | Server accepted and named the UUID |
| `telemetry_event_rejected_by_server` | Server refused it; `server_response` and `payload_sent` say why |
| No `telemetry_event_saved` at all | The event was never created |

---

## 10. Prove what the server accepts (no phone needed)

`tools/telemetry_probe.ps1` logs in with your own account and sends three
requests:

| Probe | Payload | Purpose |
| --- | --- | --- |
| A | Minimal `offline_started` (same as `test_api.sh`) | Is the account/endpoint healthy? |
| B | **Exactly** what the app sends now | Does the server accept our real payload? |
| C | Same event with `null` fields (old app shape) | Does the server refuse nulls? |

Run it:

```powershell
$env:PROBE_EMAIL="your@email.com"
$env:PROBE_PASSWORD="your-password"
powershell -ExecutionPolicy Bypass -File tools/telemetry_probe.ps1
```

Reading the verdict:

- **B = 200** -> the backend format is fine; the phone was not uploading. The
  60-second heartbeat + immediate upload is the fix.
- **B = 400/422** -> the server prints the field it dislikes. That text is sent
  to the backend engineer (and is also visible in
  `telemetry_event_rejected_by_server`).
- **A fails too** -> the problem is the login/API key/endpoint, not telemetry.

