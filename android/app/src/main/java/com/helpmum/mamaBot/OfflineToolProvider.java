package com.helpmum.mamaBot;

import android.content.res.AssetManager;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.ai.edge.litertlm.InternalJsonTool;
import com.google.ai.edge.litertlm.ToolProvider;

import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Allowlisted implementation of the active local retrieval tool.
 *
 * Model arguments are validated from the packaged contract. Runtime context
 * is supplied separately to every handler through {@link ToolContext}.
 */
final class OfflineToolProvider extends ToolProvider {
    private final String userId;
    private final String sessionId;
    private final String userQuery;
    private final ToolContext toolContext;
    private final LocalRagStore rag;
    private final Map<String, InternalJsonTool> tools = new LinkedHashMap<>();
    private final JsonObject contract;
    private final JsonArray calls = new JsonArray();
    private List<LocalRagStore.RetrievedPassage> lastRetrievalPassages = new ArrayList<>();
    private int turnNumber;

    OfflineToolProvider(
            String userId,
            String sessionId,
            String userQuery,
            LocalRagStore rag,
            AssetManager assets) {
        this.userId = requireScope(userId, "user_id");
        this.sessionId = requireScope(sessionId, "session_id");
        this.userQuery = userQuery == null ? "" : userQuery;
        this.toolContext = new ToolContext(this.userId, this.sessionId, this.userQuery);
        this.rag = rag;
        this.contract = loadContract(assets);
        register("oncall_rag", this::oncallRag);
    }

    private void register(String name, Handler handler) {
        tools.put(name, contractTool(name, handler));
    }

    void beginTurn(int number) {
        turnNumber = number;
        calls.asList().clear();
        lastRetrievalPassages = new ArrayList<>();
    }

    JsonArray drainCalls() {
        JsonArray copy = calls.deepCopy();
        calls.asList().clear();
        return copy;
    }

    List<LocalRagStore.RetrievedPassage> drainRetrievalPassages() {
        List<LocalRagStore.RetrievedPassage> copy = new ArrayList<>(lastRetrievalPassages);
        lastRetrievalPassages = new ArrayList<>();
        return copy;
    }

    JsonElement executeRequested(JsonObject call) {
        String name;
        if (call.has("name")) name = call.get("name").getAsString();
        else if (call.has("function")) {
            name = call.getAsJsonObject("function").get("name").getAsString();
        } else {
            throw new IllegalArgumentException("tool call has no name");
        }
        JsonElement rawArguments = call.has("arguments")
                ? call.get("arguments")
                : call.getAsJsonObject("function").get("arguments");
        JsonObject arguments;
        if (rawArguments != null && rawArguments.isJsonObject()) {
            arguments = rawArguments.getAsJsonObject();
        } else if (rawArguments != null && rawArguments.isJsonPrimitive()) {
            arguments = JsonParser.parseString(rawArguments.getAsString()).getAsJsonObject();
        } else {
            throw new IllegalArgumentException("tool call arguments must be an object");
        }
        String callId = call.has("id") && !call.get("id").isJsonNull()
                ? call.get("id").getAsString() : null;
        if (call.has("function") && call.get("function").isJsonObject()) {
            JsonObject function = call.getAsJsonObject("function");
            if (callId == null && function.has("id") && !function.get("id").isJsonNull()) {
                callId = function.get("id").getAsString();
            }
        }
        InternalJsonTool tool = tools.get(name);
        if (tool == null) throw new IllegalArgumentException("unknown or unexposed tool: " + name);
        return ((ContractTool) tool).executeWithCallId(arguments, callId);
    }

    List<JsonObject> schemas() {
        List<JsonObject> result = new ArrayList<>();
        for (InternalJsonTool tool : tools.values()) result.add(tool.getToolDescription());
        return result;
    }

    @Override
    public Map<String, InternalJsonTool> provideTools$third_party_odml_litert_lm_kotlin_java_com_google_ai_edge_litertlm_litertlm_android() {
        return tools;
    }

    private InternalJsonTool contractTool(String name, Handler handler) {
        for (JsonElement element : contract.getAsJsonArray("tools")) {
            JsonObject definition = element.getAsJsonObject();
            if (name.equals(definition.get("name").getAsString())) {
                return new ContractTool(
                        name,
                        definition.get("description").getAsString(),
                        definition.getAsJsonObject("parameters"),
                        handler);
            }
        }
        throw new IllegalStateException("Missing tool contract entry: " + name);
    }

    private static JsonObject loadContract(AssetManager assets) {
        try (InputStreamReader reader = new InputStreamReader(
                assets.open("tool_contract.json"), StandardCharsets.UTF_8)) {
            return JsonParser.parseReader(reader).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            throw new IllegalStateException("Unable to load shared tool contract", exception);
        }
    }

    private JsonElement execute(String name, JsonObject arguments, Handler handler, String requestedCallId) {
        try {
            validate(name, arguments);
            if (RuntimePolicy.count(arguments.toString(), null)
                    > RuntimePolicy.MAX_TOOL_ARGUMENT_TOKENS) {
                throw new IllegalArgumentException("tool arguments exceed the package limit");
            }
            JsonElement value = handler.run(arguments, toolContext);
            JsonObject call = new JsonObject();
            call.addProperty("tool", name);
            call.addProperty("turn", turnNumber);
            call.addProperty("call_id", callId(requestedCallId));
            call.add("arguments", arguments.deepCopy());
            call.add("result", value.deepCopy());
            calls.add(call);
            return value;
        } catch (Throwable throwable) {
            JsonObject error = new JsonObject();
            error.addProperty("error", throwable.getMessage() == null
                    ? throwable.toString() : throwable.getMessage());
            JsonObject call = new JsonObject();
            call.addProperty("tool", name);
            call.addProperty("turn", turnNumber);
            call.addProperty("call_id", callId(requestedCallId));
            call.add("arguments", arguments.deepCopy());
            call.add("result", error.deepCopy());
            calls.add(call);
            return error;
        }
    }

    private String callId(String requestedCallId) {
        return requestedCallId == null || requestedCallId.trim().isEmpty()
                ? sessionId + "-turn-" + turnNumber + "-" + UUID.randomUUID()
                : requestedCallId;
    }

    private void validate(String name, JsonObject arguments) {
        JsonObject parameters = null;
        for (JsonElement element : contract.getAsJsonArray("tools")) {
            JsonObject definition = element.getAsJsonObject();
            if (name.equals(definition.get("name").getAsString())) {
                parameters = definition.getAsJsonObject("parameters");
                break;
            }
        }
        if (parameters == null) throw new IllegalArgumentException("tool is not allowlisted");
        validateSchema(arguments, parameters, parameters);
    }

    private static void validateSchema(JsonElement value, JsonObject schema, JsonObject root) {
        if (schema.has("anyOf")) {
            RuntimeException last = null;
            for (JsonElement option : schema.getAsJsonArray("anyOf")) {
                try {
                    validateSchema(value, option.getAsJsonObject(), root);
                    return;
                } catch (RuntimeException exception) {
                    last = exception;
                }
            }
            throw new IllegalArgumentException("argument does not match its schema", last);
        }
        if (schema.has("$ref")) {
            String reference = schema.get("$ref").getAsString();
            String definition = reference.substring(reference.lastIndexOf('/') + 1);
            validateSchema(value, root.getAsJsonObject("$defs").getAsJsonObject(definition), root);
            return;
        }
        String type = schema.has("type") ? schema.get("type").getAsString() : "";
        if ("object".equals(type)) {
            if (!value.isJsonObject()) throw new IllegalArgumentException("argument must be an object");
            JsonObject object = value.getAsJsonObject();
            if (schema.has("required")) {
                for (JsonElement item : schema.getAsJsonArray("required")) {
                    String field = item.getAsString();
                    if (!object.has(field) || object.get(field).isJsonNull()) {
                        throw new IllegalArgumentException("missing required argument: " + field);
                    }
                }
            }
            JsonObject properties = schema.has("properties")
                    ? schema.getAsJsonObject("properties") : new JsonObject();
            if (schema.has("additionalProperties")
                    && !schema.get("additionalProperties").getAsBoolean()) {
                for (String field : object.keySet()) {
                    if (!properties.has(field)) {
                        throw new IllegalArgumentException("unexpected argument: " + field);
                    }
                }
            }
            for (Map.Entry<String, JsonElement> field : object.entrySet()) {
                if (properties.has(field.getKey())) {
                    validateSchema(field.getValue(), properties.getAsJsonObject(field.getKey()), root);
                }
            }
            return;
        }
        if ("array".equals(type)) {
            if (!value.isJsonArray()) throw new IllegalArgumentException("argument must be an array");
            if (schema.has("items")) {
                for (JsonElement item : value.getAsJsonArray()) {
                    validateSchema(item, schema.getAsJsonObject("items"), root);
                }
            }
            return;
        }
        if ("string".equals(type)) {
            if (!value.isJsonPrimitive() || !value.getAsJsonPrimitive().isString()) {
                throw new IllegalArgumentException("argument must be a string");
            }
            String text = value.getAsString();
            if (schema.has("minLength") && text.length() < schema.get("minLength").getAsInt()) {
                throw new IllegalArgumentException("argument is shorter than allowed");
            }
            if (schema.has("maxLength") && text.length() > schema.get("maxLength").getAsInt()) {
                throw new IllegalArgumentException("argument is longer than allowed");
            }
            return;
        }
        if ("number".equals(type) || "integer".equals(type)) {
            if (!value.isJsonPrimitive() || !value.getAsJsonPrimitive().isNumber()) {
                throw new IllegalArgumentException("argument must be numeric");
            }
            if ("integer".equals(type) && value.getAsDouble() != Math.rint(value.getAsDouble())) {
                throw new IllegalArgumentException("argument must be an integer");
            }
            if (schema.has("minimum") && value.getAsDouble() < schema.get("minimum").getAsDouble()) {
                throw new IllegalArgumentException("argument is below the allowed minimum");
            }
            if (schema.has("maximum") && value.getAsDouble() > schema.get("maximum").getAsDouble()) {
                throw new IllegalArgumentException("argument exceeds the allowed maximum");
            }
        }
    }

    private JsonElement oncallRag(JsonObject arguments, ToolContext context) {
        if (rag == null) throw new IllegalStateException("oncall_rag requires a local RAG store");
        if (context.userQuery.trim().isEmpty()) {
            throw new IllegalArgumentException("current user message is empty");
        }
        List<LocalRagStore.RetrievedPassage> retrieved =
                Retrieval.retrieve(rag, context.userQuery, context.userId, context.sessionId);
        rag.recordRetrieval(context.userQuery, context.userId, context.sessionId, retrieved);
        List<LocalRagStore.RetrievedPassage> passages = rag.fitPassages(retrieved, null);
        if (passages.size() > 2) passages = new ArrayList<>(passages.subList(0, 2));
        lastRetrievalPassages = new ArrayList<>(passages);
        StringBuilder result = new StringBuilder();
        for (LocalRagStore.RetrievedPassage passage : passages) {
            if (result.length() > 0) result.append('\n');
            result.append(passage.text);
        }
        return new com.google.gson.JsonPrimitive(result.toString());
    }

    private static String requireScope(String value, String name) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(name + " must not be empty");
        }
        return value;
    }

    interface Handler { JsonElement run(JsonObject arguments, ToolContext context); }

    static final class ToolContext {
        final String userId;
        final String sessionId;
        final String userQuery;

        ToolContext(String userId, String sessionId, String userQuery) {
            this.userId = userId;
            this.sessionId = sessionId;
            this.userQuery = userQuery;
        }
    }

    private final class ContractTool implements InternalJsonTool {
        private final String name;
        private final String description;
        private final JsonObject parameters;
        private final Handler handler;

        ContractTool(String name, String description, JsonObject parameters, Handler handler) {
            this.name = name;
            this.description = description;
            this.parameters = parameters;
            this.handler = handler;
        }

        @Override public JsonObject getToolDescription() {
            JsonObject value = new JsonObject();
            value.addProperty("name", name);
            value.addProperty("description", description);
            value.add("parameters", parameters.deepCopy());
            return value;
        }

        @Override public Object execute(JsonObject arguments) {
            return OfflineToolProvider.this.execute(name, arguments, handler, null);
        }

        JsonElement executeWithCallId(JsonObject arguments, String callId) {
            return OfflineToolProvider.this.execute(name, arguments, handler, callId);
        }
    }
}
