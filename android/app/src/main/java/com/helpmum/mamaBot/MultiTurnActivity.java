package com.helpmum.mamaBot;

import android.app.Activity;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.util.Log;

import com.google.ai.edge.litertlm.Contents;
import com.google.ai.edge.litertlm.Conversation;
import com.google.ai.edge.litertlm.ConversationConfig;
import com.google.ai.edge.litertlm.Engine;
import com.google.ai.edge.litertlm.EngineConfig;
import com.google.ai.edge.litertlm.InternalJsonTool;
import com.google.ai.edge.litertlm.Message;
import com.google.ai.edge.litertlm.ThinkingConfig;
import com.google.ai.edge.litertlm.ToolProvider;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.Collections;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** File-backed continuous-conversation bridge for the multi-turn benchmark. */
public final class MultiTurnActivity extends Activity {
    private static final String TAG = "LiteRTLMMultiTurn";
    private static final String MODEL_PATH = "/data/local/tmp/gemma-4-E2B-it.litertlm";
    private static final String REQUESTS = "/data/local/tmp/gemma-multiturn-requests.jsonl";
    private static final String RESULTS_NAME = "gemma-multiturn-results.jsonl";
    private static final int MAX_HISTORY_TURNS = 5;
    private long loadMs = -1L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        new Thread(this::runBenchmark, "litertlm-multiturn").start();
    }

    private void runBenchmark() {
        Engine engine = null;
        long loadStart = System.nanoTime();
        try {
            EngineConfig engineConfig = RuntimeTuning.createEngineConfig(this, MODEL_PATH);
            engine = new Engine(engineConfig);
            engine.initialize();
            loadMs = elapsedMillis(loadStart);
            log("load_ms=" + loadMs
                    + " backend=" + RuntimeTuning.backendName(this)
                    + " cache_dir=" + RuntimeTuning.cachePath(this));
            File results = new File(getFilesDir(), RESULTS_NAME);
            try (BufferedReader input = new BufferedReader(new FileReader(REQUESTS));
                    BufferedWriter output = new BufferedWriter(new FileWriter(results, false))) {
                String line;
                while ((line = input.readLine()) != null) {
                    if (line.trim().isEmpty()) {
                        continue;
                    }
                    JsonObject request = JsonParser.parseString(line).getAsJsonObject();
                    output.write(runConversation(engine, request).toString());
                    output.newLine();
                    output.flush();
                }
            }
            log("multiturn=COMPLETE");
        } catch (Throwable throwable) {
            log("multiturn=ERROR type=" + throwable.getClass().getName()
                    + " message=" + throwable.getMessage());
        } finally {
            closeQuietly(engine);
        }
    }

    private JsonObject runConversation(Engine engine, JsonObject request) {
        JsonObject result = new JsonObject();
        String conversationId = request.has("conversation_id")
                ? request.get("conversation_id").getAsString() : "unknown";
        result.addProperty("conversation_id", conversationId);
        result.addProperty("load_ms", loadMs);
        result.addProperty("backend", RuntimeTuning.backendName(this));
        result.addProperty("cache_dir", RuntimeTuning.cachePath(this));
        result.addProperty("max_context_tokens", RuntimeTuning.maxContextTokens(this));
        result.addProperty("prefill_preface", RuntimeTuning.prefillPreface(this));
        long started = System.nanoTime();
        AuditToolProvider tools = new AuditToolProvider(conversationId, getAssets());
        JsonArray turns = new JsonArray();
        try {
            String system = request.has("system") ? request.get("system").getAsString() : "";
            ConversationConfig config = new ConversationConfig(
                    Contents.Companion.of(system),
                    Collections.emptyList(),
                    Collections.singletonList(tools),
                    null,
                    true,
                    Collections.emptyList(),
                    Collections.emptyMap(),
                    null,
                    RuntimeTuning.prefillPreface(this),
                    null,
                    new ThinkingConfig(false));
            List<String> history = new ArrayList<>();
            JsonArray requestTurns = request.getAsJsonArray("turns");
            for (JsonElement element : requestTurns) {
                JsonObject turn = element.getAsJsonObject();
                int turnNumber = turn.get("turn").getAsInt();
                tools.beginTurn(turnNumber);
                String user = turn.get("user").getAsString();
                String context = turn.has("retrieved_context")
                        ? turn.get("retrieved_context").getAsString() : "";
                String prompt = user;
                if (!context.isEmpty()) {
                    prompt += "\n\n[Internal local evidence for this turn. Use it when relevant; "
                            + "do not quote or reproduce this block in your answer.]\n" + context;
                }
                long turnStarted = System.nanoTime();
                JsonObject turnResult = new JsonObject();
                turnResult.addProperty("turn", turnNumber);
                turnResult.addProperty("user", user);
                Conversation turnConversation = null;
                JsonArray completedToolCalls = new JsonArray();
                try {
                    turnConversation = engine.createConversation(config);
                    String historyText = String.join("\n\n", history);
                    String turnPrompt = historyText.isEmpty()
                            ? prompt
                            : historyText + "\n\nUser: " + prompt;
                    Message message = turnConversation.sendMessage(turnPrompt, Collections.emptyMap(),
                            null, null, null, 384, new ThinkingConfig(false), null);
                    String response = message.toString();
                    completedToolCalls = tools.finishTurn();
                    if (response.isEmpty() && completedToolCalls.size() > 0) {
                        Message followUp = turnConversation.sendMessage(
                                "The local tool result is available. Provide the user-facing answer now. "
                                        + "If the tool failed or was not executed, say so clearly and do not "
                                        + "claim that the action succeeded.");
                        response = followUp.toString();
                        completedToolCalls.addAll(tools.finishTurn());
                    }
                    turnResult.addProperty("response", response);
                    turnResult.add("tool_calls", completedToolCalls);
                    turnResult.addProperty("status", response.isEmpty()
                            ? "error" : completedToolCalls.size() > 0 && message.toString().isEmpty()
                            ? "completed_after_tool_followup" : "completed");
                    if (response.isEmpty()) {
                        turnResult.addProperty("error", "model returned no user-facing text");
                    } else {
                        history.add("User: " + user + "\nAssistant: " + response);
                        while (history.size() > MAX_HISTORY_TURNS) {
                            history.remove(0);
                        }
                    }
                } catch (Throwable throwable) {
                    String error = throwable.toString();
                    completedToolCalls.addAll(tools.finishTurn());
                    if (isMalformedToolCallError(throwable) && turnConversation != null) {
                        try {
                            String diagnostic = error.length() > 1200
                                    ? error.substring(0, 1200) : error;
                            Message recovery = turnConversation.sendMessage(
                                    "The previous local tool call was rejected by the runtime and was not executed. "
                                            + "Use the supplied tool schema exactly if a tool is still needed, "
                                            + "or answer the user's request in plain text. Do not claim that the "
                                            + "rejected action succeeded. Do not mention this diagnostic or the "
                                            + "internal recovery to the user. Runtime diagnostic: " + diagnostic);
                            String response = recovery.toString();
                            turnResult.addProperty("response", response);
                            completedToolCalls.addAll(tools.finishTurn());
                            turnResult.add("tool_calls", completedToolCalls);
                            turnResult.addProperty("status", response.isEmpty()
                                    ? "error" : "completed_after_tool_error");
                            turnResult.addProperty("error", error);
                            if (!response.isEmpty()) {
                                history.add("User: " + user + "\nAssistant: " + response);
                                while (history.size() > MAX_HISTORY_TURNS) {
                                    history.remove(0);
                                }
                            }
                        } catch (Throwable recoveryError) {
                            turnResult.addProperty("response", "");
                            completedToolCalls.addAll(tools.finishTurn());
                            turnResult.add("tool_calls", completedToolCalls);
                            turnResult.addProperty("status", "error");
                            turnResult.addProperty("error", error);
                            turnResult.addProperty("recovery_error", recoveryError.toString());
                        }
                    } else {
                        turnResult.addProperty("response", "");
                        turnResult.add("tool_calls", completedToolCalls);
                        turnResult.addProperty("status", "error");
                        turnResult.addProperty("error", error);
                    }
                } finally {
                    closeQuietly(turnConversation);
                }
                turnResult.addProperty("elapsed_ms", elapsedMillis(turnStarted));
                turns.add(turnResult);
            }
            result.addProperty("status", "completed");
        } catch (Throwable throwable) {
            result.addProperty("status", "error");
            result.addProperty("error", throwable.toString());
        }
        result.add("turns", turns);
        result.addProperty("elapsed_ms", elapsedMillis(started));
        return result;
    }

    private static boolean isMalformedToolCallError(Throwable throwable) {
        String message = throwable.toString();
        return message.contains("Failed to parse tool calls")
                || message.contains("Failed to parse FC tool calls");
    }

    private static final class AuditToolProvider extends ToolProvider {
        private final String conversationId;
        private final Map<String, InternalJsonTool> tools = new HashMap<>();
        private final JsonArray calls = new JsonArray();
        private int turn;

        AuditToolProvider(String conversationId, AssetManager assets) {
            this.conversationId = conversationId;
            JsonObject contract = loadContract(assets);
            tools.put("calculate_pregnancy_dates", contractTool(contract, "calculate_pregnancy_dates", this::calculatePregnancyDates));
            tools.put("get_immunization_status", contractTool(contract, "get_immunization_status", this::immunizationStatus));
            tools.put("save_health_record", contractTool(contract, "save_health_record", this::saveHealthRecord));
            tools.put("create_reminder", contractTool(contract, "create_reminder", this::createReminder));
            tools.put("convert_measurement", contractTool(contract, "convert_measurement", this::convertMeasurement));
        }

        private static Tool contractTool(JsonObject contract, String name, ToolHandler handler) {
            for (JsonElement element : contract.getAsJsonArray("tools")) {
                JsonObject definition = element.getAsJsonObject();
                if (name.equals(definition.get("name").getAsString())) {
                    return new Tool(
                            name,
                            definition.get("description").getAsString(),
                            definition.getAsJsonObject("parameters"),
                            handler);
                }
            }
            throw new IllegalStateException("Missing tool contract entry: " + name);
        }

        private static JsonObject loadContract(AssetManager assets) {
            String[] candidates = { "tool_contract.json", "contracts/tool_contract.json" };
            Exception last = null;
            for (String candidate : candidates) {
                try (InputStreamReader reader = new InputStreamReader(
                        assets.open(candidate), StandardCharsets.UTF_8)) {
                    return JsonParser.parseReader(reader).getAsJsonObject();
                } catch (IOException | RuntimeException e) { last = e; }
            }
            throw new IllegalStateException("tool_contract.json not found in Android assets", last);
        }

        void beginTurn(int turnNumber) {
            turn = turnNumber;
            calls.asList().clear();
        }

        JsonArray finishTurn() {
            JsonArray snapshot = calls.deepCopy();
            calls.asList().clear();
            return snapshot;
        }

        @Override
        public Map<String, InternalJsonTool> provideTools$third_party_odml_litert_lm_kotlin_java_com_google_ai_edge_litertlm_litertlm_android() {
            return tools;
        }

        private JsonObject audit(String name, JsonObject arguments, JsonElement result) {
            JsonObject call = new JsonObject();
            call.addProperty("tool", name);
            call.addProperty("turn", turn);
            call.add("arguments", arguments.deepCopy());
            call.add("result", result.deepCopy());
            call.addProperty("call_id", conversationId + "-turn-" + turn + "-" + UUID.randomUUID());
            calls.add(call);
            return result.isJsonObject() ? result.getAsJsonObject() : new JsonObject();
        }

        private JsonElement calculatePregnancyDates(JsonObject args) {
            try {
                LocalDate lmp = LocalDate.parse(args.get("last_menstrual_period").getAsString());
                LocalDate asOf = LocalDate.parse(args.get("as_of_date").getAsString());
                int cycle = args.has("cycle_length_days") && !args.get("cycle_length_days").isJsonNull()
                        ? args.get("cycle_length_days").getAsInt() : 28;
                long days = java.time.temporal.ChronoUnit.DAYS.between(lmp, asOf);
                JsonObject value = new JsonObject();
                value.addProperty("estimated_due_date", lmp.plusDays(280L + cycle - 28L).toString());
                value.addProperty("gestational_age_days", days);
                value.addProperty("gestational_age_weeks", days / 7);
                value.addProperty("gestational_age_remainder_days", days % 7);
                value.addProperty("cycle_length_days_used", cycle);
                value.addProperty("calculation_method", "last_menstrual_period_plus_280_days_adjusted_cycle");
                return audit("calculate_pregnancy_dates", args, value);
            } catch (Throwable throwable) {
                return error("calculate_pregnancy_dates", args, throwable);
            }
        }

        private JsonElement immunizationStatus(JsonObject args) {
            JsonObject value = new JsonObject();
            value.addProperty("schedule_version", "nigeria-fmoh-child-routine-2025-06");
            value.addProperty("schedule_name", "Nigerian National Immunization Schedule for Children");
            value.addProperty("schedule_source", "bundled local schedule");
            value.addProperty("child_date_of_birth", args.get("child_date_of_birth").getAsString());
            value.addProperty("as_of_date", args.get("as_of_date").getAsString());
            JsonArray history = args.has("vaccination_history") ? args.getAsJsonArray("vaccination_history") : new JsonArray();
            JsonArray future = new JsonArray();
            LocalDate asOf = LocalDate.parse(args.get("as_of_date").getAsString());
            for (JsonElement element : history) {
                JsonObject record = element.getAsJsonObject();
                if (LocalDate.parse(record.get("administered_on").getAsString()).isAfter(asOf)) {
                    future.add(record.deepCopy());
                }
            }
            value.add("future_dated_records", future);
            value.add("received_records", history.deepCopy());
            value.addProperty("next_step_for_due_or_missed", "take the child's record to a health worker for catch-up guidance");
            value.addProperty("calculation_scope", "routine schedule only; no catch-up or campaign doses inferred");
            return audit("get_immunization_status", args, value);
        }

        private JsonElement saveHealthRecord(JsonObject args) {
            String recordType = args.get("record_type").getAsString();
            if (!recordType.equals("pregnancy") && !recordType.equals("postpartum")
                    && !recordType.equals("newborn") && !recordType.equals("immunization")
                    && !recordType.equals("measurement") && !recordType.equals("other")) {
                return error("save_health_record", args,
                        new IllegalArgumentException("record_type must be pregnancy, postpartum, newborn, immunization, measurement or other"));
            }
            parseDateTime(args.get("recorded_at").getAsString());
            if (!args.has("record") || !args.get("record").isJsonObject()) {
                return error("save_health_record", args,
                        new IllegalArgumentException("record must be an object"));
            }
            JsonObject value = new JsonObject();
            value.addProperty("record_id", "record-" + conversationId + "-turn-" + turn);
            value.addProperty("status", "saved_locally");
            value.addProperty("record_type", recordType);
            value.addProperty("recorded_at", args.get("recorded_at").getAsString());
            value.add("record", args.getAsJsonObject("record").deepCopy());
            return audit("save_health_record", args, value);
        }

        private JsonElement createReminder(JsonObject args) {
            String category = args.get("category").getAsString();
            if (!category.equals("antenatal") && !category.equals("postnatal")
                    && !category.equals("immunization") && !category.equals("medication")
                    && !category.equals("follow_up") && !category.equals("other")) {
                return error("create_reminder", args,
                        new IllegalArgumentException("category must be antenatal, postnatal, immunization, medication, follow_up or other"));
            }
            parseDateTime(args.get("due_at").getAsString());
            JsonObject value = new JsonObject();
            value.addProperty("reminder_id", "reminder-" + conversationId + "-turn-" + turn);
            value.addProperty("status", "scheduled_locally");
            value.addProperty("title", args.get("title").getAsString());
            value.addProperty("due_at", args.get("due_at").getAsString());
            value.addProperty("category", category);
            if (args.has("notes")) value.add("notes", args.get("notes").deepCopy());
            if (args.has("recurrence")) value.add("recurrence", args.get("recurrence").deepCopy());
            return audit("create_reminder", args, value);
        }

        private JsonElement convertMeasurement(JsonObject args) {
            try {
                double value = args.get("value").getAsDouble();
                String from = args.get("from_unit").getAsString().toLowerCase();
                String to = args.get("to_unit").getAsString().toLowerCase();
                double converted;
                if ((from.equals("f") || from.equals("fahrenheit"))
                        && (to.equals("c") || to.equals("celsius"))) {
                    converted = (value - 32.0) * 5.0 / 9.0;
                } else if ((from.equals("c") || from.equals("celsius"))
                        && (to.equals("f") || to.equals("fahrenheit"))) {
                    converted = (value * 9.0 / 5.0) + 32.0;
                } else if (from.equals("kg") && (to.equals("lb") || to.equals("lbs") || to.equals("pound") || to.equals("pounds"))) {
                    converted = value * 2.2046226218;
                } else if ((from.equals("lb") || from.equals("lbs") || from.equals("pound") || from.equals("pounds")) && to.equals("kg")) {
                    converted = value / 2.2046226218;
                } else if ((from.equals("in") || from.equals("inch") || from.equals("inches"))
                        && (to.equals("cm") || to.equals("centimeter") || to.equals("centimeters"))) {
                    converted = value * 2.54;
                } else if ((from.equals("cm") || from.equals("centimeter") || from.equals("centimeters"))
                        && (to.equals("in") || to.equals("inch") || to.equals("inches"))) {
                    converted = value / 2.54;
                } else if (from.equals("l") && (to.equals("ml") || to.equals("milliliter") || to.equals("milliliters"))) {
                    converted = value * 1000.0;
                } else if ((from.equals("ml") || from.equals("milliliter") || from.equals("milliliters")) && to.equals("l")) {
                    converted = value / 1000.0;
                } else if (from.equals(to)) {
                    converted = value;
                } else {
                    throw new IllegalArgumentException("unsupported conversion");
                }
                JsonObject result = new JsonObject();
                result.addProperty("value", Math.round(converted * 100.0) / 100.0);
                result.addProperty("unit", to);
                result.addProperty("measurement_type", args.get("measurement_type").getAsString());
                result.addProperty("conversion", value + " " + from + " = " + result.get("value").getAsString() + " " + to);
                return audit("convert_measurement", args, result);
            } catch (Throwable throwable) {
                return error("convert_measurement", args, throwable);
            }
        }

        private JsonElement error(String name, JsonObject args, Throwable throwable) {
            JsonObject result = new JsonObject();
            result.addProperty("error", throwable.toString());
            audit(name, args, result);
            return result;
        }
    }

    private interface ToolHandler { JsonElement run(JsonObject arguments); }

    private static final class Tool implements InternalJsonTool {
        private final String name;
        private final String description;
        private final JsonObject parameters;
        private final ToolHandler handler;

        Tool(String name, String description, JsonObject parameters, ToolHandler handler) {
            this.name = name;
            this.description = description;
            this.parameters = parameters;
            this.handler = handler;
        }

        @Override public JsonObject getToolDescription() {
            JsonObject descriptionObject = new JsonObject();
            descriptionObject.addProperty("name", name);
            descriptionObject.addProperty("description", description);
            descriptionObject.add("parameters", parameters.deepCopy());
            return descriptionObject;
        }

        @Override public Object execute(JsonObject arguments) { return handler.run(arguments); }
    }

    private static LocalDateTime parseDateTime(String value) {
        try {
            return LocalDateTime.parse(value);
        } catch (DateTimeParseException ignored) {
            return LocalDateTime.ofInstant(Instant.parse(value), java.time.ZoneOffset.UTC);
        }
    }

    private static long elapsedMillis(long startNanos) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNanos);
    }

    private static void closeQuietly(AutoCloseable closeable) {
        if (closeable == null) return;
        try { closeable.close(); } catch (Exception exception) { log("close_error=" + exception); }
    }

    private static void log(String message) {
        Log.i(TAG, message);
        System.out.println(message);
    }
}
