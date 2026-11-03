package com.example.mama_ai;

import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private static final String METHOD_CHANNEL = "mama_ai/offline_ai";
    private static final String EVENT_CHANNEL = "mama_ai/offline_ai_events";
    private static final String DEVICE_CHANNEL = "mama_ai/device_info";

    private final Gson gson = new Gson();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private OfflineAiBridge offlineAiBridge;
    private DeviceTelemetry deviceTelemetry;
    private volatile EventChannel.EventSink eventSink;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        offlineAiBridge = new OfflineAiBridge(this);
        deviceTelemetry = new DeviceTelemetry(this);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), METHOD_CHANNEL)
                .setMethodCallHandler(this::handleMethodCall);

        // Telemetry device envelope (RAM, PSS, thermal, battery, model...).
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DEVICE_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "snapshot":
                            try {
                                String backend = call.argument("backend");
                                JsonObject snapshot = deviceTelemetry.snapshot(
                                        backend == null ? "cpu" : backend);
                                result.success(toFlutterValue(snapshot));
                            } catch (Throwable error) {
                                result.error("DEVICE_INFO_ERROR", error.getMessage(), null);
                            }
                            break;
                        default:
                            result.notImplemented();
                    }
                });

        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), EVENT_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink sink) {
                        eventSink = sink;
                    }
                    @Override
                    public void onCancel(Object arguments) {
                        eventSink = null;
                    }
                });
    }

    private void handleMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "initialize":
                    runVoid(result, () -> offlineAiBridge.initialize(asJsonObject(call.arguments)));
                    break;
                case "generate":
                    JsonObject request = asJsonObject(call.arguments);
                    startGenerate(request);
                    result.success(null);
                    break;
                case "cancel":
                    offlineAiBridge.cancel(requiredArgument(call.arguments, "chat_id"));
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Throwable error) { // CATCH THROWABLE INSTEAD OF RUNTIMEEXCEPTION
            result.error("INVALID_ARGUMENT", error.getMessage(), null);
        }
    }

    private void runVoid(MethodChannel.Result result, Runnable work) {
        executor.execute(() -> {
            try {
                work.run();
                reply(result, null);
            } catch (Throwable error) { // Safe catch for native C++ failures
                replyError(result, "RUNTIME_ERROR", error);
            }
        });
    }

    private void startGenerate(JsonObject request) {
        executor.execute(() -> {
            try {
                offlineAiBridge.generate(request, this::emitEvent);
            } catch (Throwable error) { // Prevents app crashes on native inference failures
                JsonObject event = new JsonObject();
                event.addProperty("event", "error");
                event.addProperty("request_id", request.has("request_id") ? request.get("request_id").getAsString() : "unknown");
                event.addProperty("chat_id", request.has("chat_id") ? request.get("chat_id").getAsString() : "unknown");
                event.addProperty("error_type", error.getClass().getName());
                event.addProperty("error", error.getMessage() == null ? error.toString() : error.getMessage());
                emitEvent(event);
            }
        });
    }

    private void emitEvent(JsonObject event) {
        Object payload = toFlutterValue(event);
        mainHandler.post(() -> {
            if (eventSink != null) eventSink.success(payload);
        });
    }

    private void reply(MethodChannel.Result result, Object value) {
        mainHandler.post(() -> result.success(value));
    }

    private void replyError(MethodChannel.Result result, String code, Throwable error) {
        mainHandler.post(() -> result.error(code, error.getMessage(), null));
    }

    private JsonObject asJsonObject(Object arguments) {
        if (!(arguments instanceof Map)) throw new IllegalArgumentException("arguments must be a map");
        JsonElement json = gson.toJsonTree(arguments);
        if (!json.isJsonObject()) throw new IllegalArgumentException("arguments must be a JSON object");
        return json.getAsJsonObject();
    }

    private String requiredArgument(Object arguments, String field) {
        return asJsonObject(arguments).get(field).getAsString();
    }

    private Object toFlutterValue(JsonElement value) {
        if (value == null || value.isJsonNull()) return null;
        if (value.isJsonObject()) {
            Map<String, Object> map = new LinkedHashMap<>();
            for (Map.Entry<String, JsonElement> entry : value.getAsJsonObject().entrySet()) {
                map.put(entry.getKey(), toFlutterValue(entry.getValue()));
            }
            return map;
        }
        if (value.isJsonArray()) {
            List<Object> list = new ArrayList<>();
            for (JsonElement item : value.getAsJsonArray()) list.add(toFlutterValue(item));
            return list;
        }
        // Keep integers as integers. gson.fromJson(..., Object.class) turns
        // EVERY number into a Double (android_api 31 becomes 31.0), which makes
        // the telemetry metadata look wrong to the backend.
        var primitive = value.getAsJsonPrimitive();
        if (primitive.isBoolean()) return primitive.getAsBoolean();
        if (primitive.isNumber()) {
            String raw = primitive.getAsString();
            boolean wholeNumber = raw.indexOf('.') < 0
                    && raw.indexOf('e') < 0 && raw.indexOf('E') < 0;
            if (wholeNumber) {
                try {
                    return Long.parseLong(raw);
                } catch (NumberFormatException ignored) {
                    // Fall through to double for very large values.
                }
            }
            return primitive.getAsDouble();
        }
        return primitive.getAsString();
    }

    @Override
    protected void onDestroy() {
        eventSink = null;
        if (offlineAiBridge != null) offlineAiBridge.close();
        executor.shutdownNow();
        super.onDestroy();
    }
}