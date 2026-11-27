package com.helpmum.mamaBot;

import android.content.Context;

import com.google.gson.JsonObject;

/**
 * JSON method boundary for a Flutter MethodChannel or FFI adapter.
 *
 * The Flutter layer can map method names to this class without giving the
 * inference runtime ownership of sync, telemetry or UI state.
 */
public final class OfflineAiBridge implements AutoCloseable {
    private final OfflineMamaAiRuntime runtime;

    public OfflineAiBridge(Context context) {
        runtime = new OfflineMamaAiRuntime(context);
    }

    public void initialize(JsonObject arguments) {
        String backend = arguments.has("backend") && !arguments.get("backend").isJsonNull()
                ? arguments.get("backend").getAsString() : "cpu";
        int maxContextTokens = arguments.has("max_context_tokens")
                ? arguments.get("max_context_tokens").getAsInt() : 4096;
        boolean prefillPreface = arguments.has("prefill_preface")
                && arguments.get("prefill_preface").getAsBoolean();
        String model = optional(arguments, "model");
        runtime.initialize(
                required(arguments, "model_path"),
                required(arguments, "knowledge_path"),
                required(arguments, "runtime_path"),
                backend,
                maxContextTokens,
                prefillPreface,
                model);
    }

    public void generate(JsonObject arguments, OfflineMamaAiRuntime.EventSink sink) {
        runtime.generate(arguments, sink);
    }

    public void cancel(String chatId) {
        runtime.cancel(chatId);
    }

    public JsonObject addDocument(JsonObject arguments) {
        LocalRagStore.DocumentRecord record = runtime.addDocument(
                android.util.Base64.decode(required(arguments, "content_base64"), android.util.Base64.DEFAULT),
                required(arguments, "display_name"),
                required(arguments, "user_id"),
                required(arguments, "session_id"));
        return record.toJson();
    }

    public void deleteDocument(JsonObject arguments) {
        runtime.deleteDocument(
                required(arguments, "document_id"),
                required(arguments, "user_id"),
                required(arguments, "session_id"));
    }

    @Override public void close() { runtime.close(); }

    private static String required(JsonObject object, String field) {
        if (!object.has(field) || object.get(field).isJsonNull()
                || object.get(field).getAsString().trim().isEmpty()) {
            throw new IllegalArgumentException(field + " must not be empty");
        }
        return object.get(field).getAsString();
    }

    private static String optional(JsonObject object, String field) {
        if (!object.has(field) || object.get(field).isJsonNull()) return null;
        String value = object.get(field).getAsString().trim();
        return value.isEmpty() ? null : value;
    }
}
