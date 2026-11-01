package com.example.mama_ai;

import android.content.res.AssetManager;
import android.database.sqlite.SQLiteDatabase;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.ai.edge.litertlm.InternalJsonTool;
import com.google.ai.edge.litertlm.ToolProvider;

import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Allowlisted local tool implementation ported from lib/tooling.
 */
final class OfflineToolProvider extends ToolProvider {
    private final String userId;
    private final String sessionId;
    private final SQLiteDatabase database;
    private final Map<String, InternalJsonTool> tools = new LinkedHashMap<>();
    private final JsonObject contract;
    private final Set<String> selectedNames;
    private final JsonArray calls = new JsonArray();
    private int turnNumber;

    OfflineToolProvider(String userId, String sessionId, SQLiteDatabase database, AssetManager assets) {
        this(userId, sessionId, database, assets, null);
    }

    OfflineToolProvider(String userId, String sessionId, SQLiteDatabase database,
                        AssetManager assets, Set<String> selectedNames) {
        this.userId = requireScope(userId, "user_id");
        this.sessionId = requireScope(sessionId, "session_id");
        this.database = database;
        this.contract = loadContract(assets);
        this.selectedNames = selectedNames == null ? null : new HashSet<>(selectedNames);
        register("calculate_pregnancy_dates", this::calculatePregnancyDates);
        register("get_immunization_status", this::immunizationStatus);
        register("save_health_record", this::saveHealthRecord);
        register("create_reminder", this::createReminder);
        register("convert_measurement", this::convertMeasurement);
        if (selectedNames != null && !tools.keySet().containsAll(selectedNames)) {
            Set<String> unknown = new HashSet<>(selectedNames);
            unknown.removeAll(tools.keySet());
            throw new IllegalArgumentException("unknown local tools requested: " + unknown);
        }
    }

    private void register(String name, Handler handler) {
        if (selectedNames == null || selectedNames.contains(name)) tools.put(name, contractTool(name, handler));
    }

    void beginTurn(int number) {
        turnNumber = number;
        calls.asList().clear();
    }

    JsonArray drainCalls() {
        JsonArray copy = calls.deepCopy();
        calls.asList().clear();
        return copy;
    }

    JsonElement executeRequested(JsonObject call) {
        String name;
        if (call.has("name")) name = call.get("name").getAsString();
        else if (call.has("function")) name = call.getAsJsonObject("function").get("name").getAsString();
        else throw new IllegalArgumentException("tool call has no name");
        JsonElement rawArguments = call.has("arguments") ? call.get("arguments")
                : call.getAsJsonObject("function").get("arguments");
        JsonObject arguments;
        if (rawArguments != null && rawArguments.isJsonObject()) arguments = rawArguments.getAsJsonObject();
        else if (rawArguments != null && rawArguments.isJsonPrimitive()) {
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
        if (!(tool instanceof ContractTool)) {
            throw new IllegalArgumentException("tool is not backed by the local contract");
        }
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
                return new ContractTool(name, definition.get("description").getAsString(),
                        definition.getAsJsonObject("parameters"), handler);
            }
        }
        throw new IllegalStateException("Missing tool contract entry: " + name);
    }

    // REPLACED loadContract(...) method with multi-candidate search
    private static JsonObject loadContract(AssetManager assets) {
        String[] candidates = { "tool_contract.json", "contracts/tool_contract.json" };
        Exception last = null;
        for (String candidate : candidates) {
            try (InputStreamReader reader = new InputStreamReader(assets.open(candidate), StandardCharsets.UTF_8)) {
                return JsonParser.parseReader(reader).getAsJsonObject();
            } catch (IOException | RuntimeException e) { last = e; }
        }
        throw new IllegalStateException("tool_contract.json not found in Android assets", last);
    }

    private JsonElement execute(String name, JsonObject arguments, Handler handler) {
        return execute(name, arguments, handler, null);
    }

    private JsonElement execute(String name, JsonObject arguments, Handler handler, String requestedCallId) {
        try {
            validate(name, arguments);
            if (RuntimePolicy.count(arguments.toString(), null) > RuntimePolicy.MAX_TOOL_ARGUMENT_TOKENS) {
                throw new IllegalArgumentException("tool arguments exceed the package limit");
            }
            JsonElement value = handler.run(arguments);
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
        if (parameters.has("required")) {
            for (JsonElement item : parameters.getAsJsonArray("required")) {
                String field = item.getAsString();
                if (!arguments.has(field) || arguments.get(field).isJsonNull()) {
                    throw new IllegalArgumentException("missing required argument: " + field);
                }
            }
        }
        if (parameters.has("additionalProperties") && !parameters.get("additionalProperties").getAsBoolean()) {
            Set<String> allowed = parameters.getAsJsonObject("properties").keySet();
            for (String field : arguments.keySet()) {
                if (!allowed.contains(field)) throw new IllegalArgumentException("unexpected argument: " + field);
            }
        }
        validateSchema(arguments, parameters, parameters);
        validateNestedAndEnums(name, arguments);
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
        if (value == null || value.isJsonNull()) {
            if (!"null".equals(schema.get("type").getAsString())) {
                throw new IllegalArgumentException("argument must not be null");
            }
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
            if (schema.has("enum")) {
                boolean found = false;
                for (JsonElement option : schema.getAsJsonArray("enum")) {
                    if (text.equals(option.getAsString())) found = true;
                }
                if (!found) throw new IllegalArgumentException("argument has an unsupported value");
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

    private void validateNestedAndEnums(String name, JsonObject args) {
        if ("calculate_pregnancy_dates".equals(name)) {
            LocalDate lmp = date(args, "last_menstrual_period");
            LocalDate asOf = date(args, "as_of_date");
            if (asOf.isBefore(lmp)) throw new IllegalArgumentException("as_of_date cannot precede last_menstrual_period");
            if (args.has("cycle_length_days") && !args.get("cycle_length_days").isJsonNull()) {
                int cycle = args.get("cycle_length_days").getAsInt();
                if (cycle < 21 || cycle > 45) throw new IllegalArgumentException("cycle_length_days must be from 21 through 45");
            }
        } else if ("get_immunization_status".equals(name)) {
            LocalDate birth = date(args, "child_date_of_birth");
            LocalDate asOf = date(args, "as_of_date");
            if (asOf.isBefore(birth)) throw new IllegalArgumentException("as_of_date cannot precede child_date_of_birth");
            if (args.has("vaccination_history")) {
                for (JsonElement item : args.getAsJsonArray("vaccination_history")) {
                    JsonObject record = item.getAsJsonObject();
                    if (!record.has("vaccine") || !record.has("administered_on")) {
                        throw new IllegalArgumentException("vaccination history requires vaccine and administered_on");
                    }
                    if (record.get("vaccine").getAsString().length() < 1 || record.get("vaccine").getAsString().length() > 120) {
                        throw new IllegalArgumentException("vaccine label length is invalid");
                    }
                    date(record, "administered_on");
                }
            }
        } else if ("save_health_record".equals(name)) {
            requireOneOf(args.get("record_type").getAsString(), "pregnancy", "postpartum", "newborn", "immunization", "measurement", "other");
            dateTime(args.get("recorded_at").getAsString());
            if (!args.get("record").isJsonObject()) throw new IllegalArgumentException("record must be an object");
        } else if ("create_reminder".equals(name)) {
            String title = args.get("title").getAsString();
            if (title.isEmpty() || title.length() > 200) throw new IllegalArgumentException("title length is invalid");
            dateTime(args.get("due_at").getAsString());
            requireOneOf(args.get("category").getAsString(), "antenatal", "postnatal", "immunization", "medication", "follow_up", "other");
            if (args.has("notes") && !args.get("notes").isJsonNull() && args.get("notes").getAsString().length() > 1000) {
                throw new IllegalArgumentException("notes exceed the package limit");
            }
            if (args.has("recurrence") && !args.get("recurrence").isJsonNull() && args.get("recurrence").getAsString().length() > 100) {
                throw new IllegalArgumentException("recurrence exceeds the package limit");
            }
        } else if ("convert_measurement".equals(name)) {
            requireOneOf(args.get("measurement_type").getAsString(), "temperature", "weight", "length", "volume");
            requireOneOf(args.get("from_unit").getAsString(), "celsius", "fahrenheit", "kg", "lb", "in", "cm", "l", "ml");
            requireOneOf(args.get("to_unit").getAsString(), "celsius", "fahrenheit", "kg", "lb", "in", "cm", "l", "ml");
        }
    }

    private JsonElement calculatePregnancyDates(JsonObject args) {
        LocalDate lmp = date(args, "last_menstrual_period");
        LocalDate asOf = date(args, "as_of_date");
        int cycle = args.has("cycle_length_days") && !args.get("cycle_length_days").isJsonNull()
                ? args.get("cycle_length_days").getAsInt() : 28;
        long days = ChronoUnit.DAYS.between(lmp, asOf);
        JsonObject result = new JsonObject();
        result.addProperty("estimated_due_date", lmp.plusDays(280L + cycle - 28L).toString());
        result.addProperty("gestational_age_days", days);
        result.addProperty("gestational_age_weeks", days / 7);
        result.addProperty("gestational_age_remainder_days", days % 7);
        result.addProperty("cycle_length_days_used", cycle);
        result.addProperty("calculation_method", "last_menstrual_period_plus_280_days_adjusted_cycle");
        return result;
    }

    private JsonElement immunizationStatus(JsonObject args) {
        LocalDate birth = date(args, "child_date_of_birth");
        LocalDate asOf = date(args, "as_of_date");
        JsonArray records = args.has("vaccination_history") ? args.getAsJsonArray("vaccination_history") : new JsonArray();
        Map<String, JsonObject> received = new HashMap<>();
        JsonArray future = new JsonArray();
        JsonArray invalid = new JsonArray();
        JsonArray unrecognized = new JsonArray();
        Set<String> recognized = new HashSet<>();
        for (ScheduleEntry entry : schedule()) recognized.add(entry.id);
        for (JsonElement element : records) {
            JsonObject record = element.getAsJsonObject();
            LocalDate administered = date(record, "administered_on");
            if (administered.isBefore(birth)) invalid.add(record.deepCopy());
            else if (administered.isAfter(asOf)) future.add(record.deepCopy());
            else {
                String vaccineId = normalizeVaccine(record.get("vaccine").getAsString());
                received.putIfAbsent(vaccineId, record);
                if (!recognized.contains(vaccineId)) unrecognized.add(record.deepCopy());
            }
        }
        List<ScheduleEntry> schedule = schedule();
        JsonArray statuses = new JsonArray();
        int receivedCount = 0;
        int dueCount = 0;
        int notDueCount = 0;
        for (ScheduleEntry entry : schedule) {
            LocalDate minimum = birth.plusDays(entry.minimumDays);
            LocalDate latest = entry.latestDays != null ? birth.plusDays(entry.latestDays)
                    : entry.latestMonths == null ? null : birth.plusMonths(entry.latestMonths);
            JsonObject record = received.get(entry.id);
            String status = record != null ? "received" : asOf.isBefore(minimum) ? "not_yet_due" : "due_or_missed";
            if ("received".equals(status)) receivedCount++;
            else if ("not_yet_due".equals(status)) notDueCount++;
            else dueCount++;
            JsonObject item = new JsonObject();
            item.addProperty("vaccine_id", entry.id);
            item.addProperty("name", entry.name);
            item.addProperty("entry_type", entry.entryType);
            if (entry.dose == null) item.add("dose", com.google.gson.JsonNull.INSTANCE);
            else item.addProperty("dose", entry.dose);
            item.addProperty("minimum_age", entry.minimumLabel);
            item.addProperty("minimum_date", minimum.toString());
            item.addProperty("scheduled_date", minimum.toString());
            if (latest != null) item.addProperty("latest_date_in_source", latest.toString());
            else item.add("latest_date_in_source", com.google.gson.JsonNull.INSTANCE);
            item.addProperty("status", status);
            item.addProperty("window_status", record != null ? "received" : latest == null ? "no_upper_age_window_encoded" : asOf.compareTo(latest) <= 0 ? "within_source_window" : "source_window_passed");
            if (record != null) item.addProperty("administered_on", record.get("administered_on").getAsString());
            else item.add("administered_on", com.google.gson.JsonNull.INSTANCE);
            item.addProperty("notes", entry.notes);
            statuses.add(item);
        }
        JsonObject result = new JsonObject();
        result.addProperty("schedule_version", "nigeria-fmoh-child-routine-2025-06");
        result.addProperty("schedule_name", "Nigerian National Immunization Schedule for Children");
        result.addProperty("schedule_source", "https://health.gov.ng/wp-content/uploads/2025/06/SCD-Guideline-Final-2nd-Edition.pdf");
        result.addProperty("child_date_of_birth", birth.toString());
        result.addProperty("as_of_date", asOf.toString());
        result.add("statuses", statuses);
        JsonObject summary = new JsonObject();
        summary.addProperty("received", receivedCount);
        summary.addProperty("not_yet_due", notDueCount);
        summary.addProperty("due_or_missed", dueCount);
        result.add("summary", summary);
        result.add("unrecognized_records", unrecognized);
        result.add("invalid_records_before_birth", invalid);
        result.add("future_dated_records", future);
        JsonObject scope = new JsonObject();
        scope.addProperty("included", "the published routine child schedule in the named source");
        JsonArray excluded = new JsonArray();
        excluded.add("catch-up dose selection");
        excluded.add("supplemental immunization campaigns");
        excluded.add("state or facility-specific schedule changes");
        excluded.add("clinical assessment of contraindications");
        scope.add("excluded", excluded);
        scope.addProperty("next_step_for_due_or_missed", "take the child's record to a health worker for catch-up guidance");
        result.add("calculation_scope", scope);
        return result;
    }

    private JsonElement saveHealthRecord(JsonObject args) {
        String id = "record-" + UUID.randomUUID().toString().replace("-", "");
        database.execSQL("INSERT INTO health_records(record_id,user_id,session_id,record_type,recorded_at,record_json) VALUES(?,?,?,?,?,?)",
                new Object[]{id, userId, sessionId, args.get("record_type").getAsString(), args.get("recorded_at").getAsString(), args.get("record").toString()});
        JsonObject result = args.deepCopy();
        result.addProperty("record_id", id);
        result.addProperty("user_id", userId);
        result.addProperty("session_id", sessionId);
        return result;
    }

    private JsonElement createReminder(JsonObject args) {
        String id = "reminder-" + UUID.randomUUID().toString().replace("-", "");
        database.execSQL("INSERT INTO reminders(reminder_id,user_id,session_id,title,due_at,category,notes,recurrence) VALUES(?,?,?,?,?,?,?,?)",
                new Object[]{id, userId, sessionId, args.get("title").getAsString(), args.get("due_at").getAsString(), args.get("category").getAsString(), nullable(args, "notes"), nullable(args, "recurrence")});
        JsonObject result = args.deepCopy();
        result.addProperty("reminder_id", id);
        result.addProperty("user_id", userId);
        result.addProperty("session_id", sessionId);
        result.addProperty("status", "scheduled");
        return result;
    }

    private JsonElement convertMeasurement(JsonObject args) {
        double value = args.get("value").getAsDouble();
        String type = args.get("measurement_type").getAsString();
        String source = args.get("from_unit").getAsString().toLowerCase(Locale.ROOT);
        String target = args.get("to_unit").getAsString().toLowerCase(Locale.ROOT);
        double converted;
        if ("temperature".equals(type)) {
            if (source.equals(target)) converted = value;
            else if (source.equals("celsius") && target.equals("fahrenheit")) converted = value * 9.0 / 5.0 + 32.0;
            else if (source.equals("fahrenheit") && target.equals("celsius")) converted = (value - 32.0) * 5.0 / 9.0;
            else throw new IllegalArgumentException("temperature units must be Celsius or Fahrenheit");
        } else {
            Map<String, Double> factors = new HashMap<>();
            if ("weight".equals(type)) { factors.put("kg", 1.0); factors.put("lb", 0.45359237); }
            if ("length".equals(type)) { factors.put("cm", 0.01); factors.put("in", 0.0254); }
            if ("volume".equals(type)) { factors.put("l", 1.0); factors.put("ml", 0.001); }
            if (!factors.containsKey(source) || !factors.containsKey(target)) throw new IllegalArgumentException("unsupported " + type + " unit conversion");
            converted = value * factors.get(source) / factors.get(target);
        }
        double rounded = BigDecimal.valueOf(converted)
                .setScale(2, RoundingMode.HALF_UP).doubleValue();
        JsonObject result = new JsonObject();
        result.addProperty("value", rounded);
        result.addProperty("unit", target);
        result.addProperty("measurement_type", type);
        result.addProperty("conversion", value + " " + source + " = " + rounded + " " + target);
        return result;
    }

    private static List<ScheduleEntry> schedule() {
        return Arrays.asList(
                new ScheduleEntry("bcg", "BCG", "vaccine", 1, "at birth", 0, null, 11, "Preferably at birth or within 2 weeks; may be given up to 11 months."),
                new ScheduleEntry("opv_0", "OPV 0", "vaccine", 0, "at birth", 0, 14, "Birth dose; the source states it must be given before 2 weeks."),
                new ScheduleEntry("hepatitis_b_birth", "Hepatitis B birth dose", "vaccine", 0, "at birth", 0, 14, "Preferably within 24 hours; the source states it may be given up to 14 days."),
                new ScheduleEntry("pentavalent_1", "Pentavalent 1", "vaccine", 1, "6 weeks", 42, null, null),
                new ScheduleEntry("pcv_1", "PCV 1", "vaccine", 1, "6 weeks", 42, null, null),
                new ScheduleEntry("opv_1", "OPV 1", "vaccine", 1, "6 weeks", 42, null, null),
                new ScheduleEntry("pentavalent_2", "Pentavalent 2", "vaccine", 2, "10 weeks", 70, null, null),
                new ScheduleEntry("pcv_2", "PCV 2", "vaccine", 2, "10 weeks", 70, null, null),
                new ScheduleEntry("opv_2", "OPV 2", "vaccine", 2, "10 weeks", 70, null, null),
                new ScheduleEntry("pentavalent_3", "Pentavalent 3", "vaccine", 3, "14 weeks", 98, null, null),
                new ScheduleEntry("pcv_3", "PCV 3", "vaccine", 3, "14 weeks", 98, null, null),
                new ScheduleEntry("opv_3", "OPV 3", "vaccine", 3, "14 weeks", 98, null, null),
                new ScheduleEntry("ipv", "IPV", "vaccine", null, "14 weeks", 98, null, null),
                new ScheduleEntry("vitamin_a_1", "Vitamin A supplement", "supplement", 1, "6 months", 182, null, "This is a supplement, not a vaccine."),
                new ScheduleEntry("measles_1", "Measles", "vaccine", 1, "9 months", 274, null, null),
                new ScheduleEntry("yellow_fever", "Yellow fever", "vaccine", 1, "9 months", 274, null, null));
    }

    private static String normalizeVaccine(String value) {
        String normalized = value.toLowerCase(Locale.ROOT).replace('-', ' ').replace('_', ' ').replaceAll("[(),]", "").replaceAll("\\s+", " ").trim();
        Map<String, String> aliases = new HashMap<>();
        aliases.put("bcg", "bcg"); aliases.put("opv 0", "opv_0"); aliases.put("opv0", "opv_0");
        aliases.put("opv 0 birth dose", "opv_0");
        aliases.put("hepatitis b0", "hepatitis_b_birth");
        aliases.put("hepatitis b birth", "hepatitis_b_birth");
        aliases.put("hepatitis b birth dose", "hepatitis_b_birth");
        aliases.put("hep b birth", "hepatitis_b_birth");
        aliases.put("hep b birth dose", "hepatitis_b_birth");
        for (String name : Arrays.asList("pentavalent", "pcv", "opv")) {
            for (int dose = 1; dose <= 3; dose++) {
                aliases.put(name + " " + dose, name + "_" + dose);
                aliases.put(name + dose, name + "_" + dose);
            }
        }
        aliases.put("penta 1", "pentavalent_1");
        aliases.put("penta 2", "pentavalent_2");
        aliases.put("penta 3", "pentavalent_3");
        aliases.put("dpt hep b hib pentavalent 1", "pentavalent_1");
        aliases.put("dpt hep b hib pentavalent 2", "pentavalent_2");
        aliases.put("dpt hep b hib pentavalent 3", "pentavalent_3");
        aliases.put("ipv", "ipv"); aliases.put("ipv 1", "ipv");
        aliases.put("inactivated polio vaccine", "ipv");
        aliases.put("inactivated polio vaccine 1", "ipv");
        aliases.put("vitamin a", "vitamin_a_1"); aliases.put("vitamin a supplement", "vitamin_a_1");
        aliases.put("measles", "measles_1"); aliases.put("measles 1", "measles_1");
        aliases.put("yellow fever", "yellow_fever"); aliases.put("yellowfever", "yellow_fever");
        return aliases.getOrDefault(normalized, normalized.replace(' ', '_'));
    }

    private static LocalDate date(JsonObject object, String field) {
        try { return LocalDate.parse(object.get(field).getAsString()); }
        catch (Exception exception) { throw new IllegalArgumentException(field + " must be an ISO date"); }
    }

    private static void dateTime(String value) {
        try { LocalDateTime.parse(value); return; }
        catch (DateTimeParseException ignored) {}
        try { OffsetDateTime.parse(value); return; }
        catch (DateTimeParseException ignored) {}
        try { java.time.Instant.parse(value); }
        catch (DateTimeParseException exception) { throw new IllegalArgumentException("timestamp must be ISO-8601"); }
    }

    private static String nullable(JsonObject object, String field) {
        return object.has(field) && !object.get(field).isJsonNull() ? object.get(field).getAsString() : null;
    }

    private static String requireScope(String value, String name) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(name + " must not be empty");
        return value;
    }

    private static void requireOneOf(String value, String... allowedValues) {
        if (!Arrays.asList(allowedValues).contains(value)) throw new IllegalArgumentException("unsupported value: " + value);
    }

    interface Handler { JsonElement run(JsonObject arguments); }

    private final class ContractTool implements InternalJsonTool {
        private final String name;
        private final String description;
        private final JsonObject parameters;
        private final Handler handler;

        ContractTool(String name, String description, JsonObject parameters, Handler handler) {
            this.name = name; this.description = description; this.parameters = parameters; this.handler = handler;
        }

        @Override public JsonObject getToolDescription() {
            JsonObject value = new JsonObject();
            value.addProperty("name", name);
            value.addProperty("description", description);
            value.add("parameters", parameters.deepCopy());
            return value;
        }

        @Override public Object execute(JsonObject arguments) {
            return OfflineToolProvider.this.execute(name, arguments, handler);
        }

        JsonElement executeWithCallId(JsonObject arguments, String callId) {
            return OfflineToolProvider.this.execute(name, arguments, handler, callId);
        }
    }

    private static final class ScheduleEntry {
        final String id, name, entryType, minimumLabel, notes;
        final Integer dose;
        final int minimumDays;
        final Integer latestDays;
        final Integer latestMonths;
        ScheduleEntry(String id, String name, String entryType, Integer dose, String minimumLabel,
                      int minimumDays, Integer latestDays, String notes) {
            this(id, name, entryType, dose, minimumLabel, minimumDays, latestDays, null, notes);
        }
        ScheduleEntry(String id, String name, String entryType, Integer dose, String minimumLabel,
                      int minimumDays, Integer latestDays, Integer latestMonths, String notes) {
            this.id = id; this.name = name; this.entryType = entryType; this.dose = dose;
            this.minimumLabel = minimumLabel; this.minimumDays = minimumDays;
            this.latestDays = latestDays; this.latestMonths = latestMonths; this.notes = notes;
        }
    }
}