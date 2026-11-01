package com.example.mama_ai;

import android.content.Context;
import android.content.res.AssetManager;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.ai.edge.litertlm.Conversation;
import com.google.ai.edge.litertlm.ConversationConfig;
import com.google.ai.edge.litertlm.Contents;
import com.google.ai.edge.litertlm.Engine;
import com.google.ai.edge.litertlm.EngineConfig;
import com.google.ai.edge.litertlm.Message;
import com.google.ai.edge.litertlm.MessageCallback;
import com.google.ai.edge.litertlm.ResponseFormat;
import com.google.ai.edge.litertlm.SamplerConfig;
import com.google.ai.edge.litertlm.ThinkingConfig;

import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Product-facing local AI runtime port.
 */
public final class OfflineMamaAiRuntime implements AutoCloseable {
    public interface EventSink {
        void emit(JsonObject event);
    }

    private final Context context;
    private final AssetManager assets;
    private Engine engine;
    private LocalRagStore rag;
    private LocalConversationStore conversations;
    private volatile Conversation activeConversation;
    private volatile boolean cancelled;
    private volatile String activeRequestId;
    private volatile String activeChatId;
    private String systemPrompt;
    private boolean prefillPreface;
    /**
     * Phase 1: how long we wait for the FIRST word. The phone must read the whole
     * prompt before it can write anything, and that can be slow on weak devices.
     */
    private static final long FIRST_TOKEN_TIMEOUT_SECONDS = 240; // 4 minutes
    /**
     * Phase 2: as soon as the first word arrives the clock is RESET and the answer
     * gets this much fresh time to finish writing. A slow phone is never cut off
     * just because the first word came late.
     */
    private static final long STREAMING_BUDGET_SECONDS = 180; // 3 minutes
    private static final String UNROUTED_SAFETY_LEVEL = "unrouted";
    private static final String UNROUTED_SAFETY_REASON =
            "No deterministic safety route is applied. The answer model must assess "
                    + "the full question and retrieved evidence.";

    public OfflineMamaAiRuntime(Context context) {
        this.context = context.getApplicationContext();
        this.assets = this.context.getAssets();
    }

    public synchronized void initialize(String modelPath, String knowledgePath, String runtimePath) {
        initialize(modelPath, knowledgePath, runtimePath, "cpu",
                RuntimePolicy.MAX_CONTEXT_TOKENS, false);
    }

    public synchronized void initialize(
            String modelPath, String knowledgePath, String runtimePath,
            String backend, int maxContextTokens, boolean prefillPreface) {
        close();

        if (!new java.io.File(modelPath).exists()) {
            throw new IllegalStateException("Model file not found: " + modelPath);
        }

        EngineConfig config = RuntimeTuning.createEngineConfig(
                context, modelPath, backend, maxContextTokens);
        engine = new Engine(config);
        engine.initialize();

        ensureKnowledgeFile(knowledgePath);
        rag = new LocalRagStore(context, knowledgePath, runtimePath);
        
        conversations = new LocalConversationStore(rag.database());
        systemPrompt = loadAsset("system_prompt.txt");
        this.prefillPreface = prefillPreface;
    }

    @Override
    public void close() {
        Conversation active = activeConversation;
        activeConversation = null;
        closeConversation(active);
        if (engine != null) {
            try { engine.close(); } catch (Throwable ignored) {}
            engine = null;
        }
        if (rag != null) {
            try { rag.close(); } catch (Throwable ignored) {}
            rag = null;
        }
    }

    private static void closeConversation(Conversation conversation) {
        if (conversation != null) {
            try { conversation.close(); } catch (Throwable ignored) {}
        }
    }

    /** Generate one complete local turn and emit normalized runtime events. */
    public void generate(JsonObject request, EventSink sink) {
        if (engine == null || rag == null) throw new IllegalStateException("runtime is not initialized");
        cancelled = false;
        String requestId = string(request, "request_id", "request-" + System.nanoTime());
        String userId = required(request, "user_id");
        String sessionId = required(request, "session_id");
        String chatId = string(request, "chat_id", sessionId);

        String activeStage = "model_load";
        int totalGeneratedTokens = 0;
        List<LocalRagStore.RetrievedPassage> passages = new ArrayList<>();
        JsonArray contextIds = new JsonArray();
        JsonArray citations = new JsonArray();
        String finalText = "";
        boolean toolWasUsed = false;
        Conversation conversation = null;

        try {
            activeStage = "model_load";
            List<ChatMessage> supplied = parseMessages(request.getAsJsonArray("messages"));
            if (supplied.isEmpty() && request.has("message")) {
                supplied.add(ChatMessage.user(textContent(request.get("message"))));
            }
            if (supplied.isEmpty()) throw new IllegalArgumentException("at least one message is required");
            ChatMessage current = supplied.get(supplied.size() - 1);
            if (!"user".equals(current.role)) throw new IllegalArgumentException("last message must be a user message");
            if (RuntimePolicy.count(current.content, null) > RuntimePolicy.MAX_INPUT_TOKENS) {
                throw new IllegalArgumentException("the user message exceeds the package input boundary");
            }

            JsonObject started = event("started", requestId, chatId);
            started.addProperty("session_id", sessionId);
            started.addProperty("safety_pending", false);
            emit(sink, started);
            conversations.append(userId, sessionId, current);

            List<ChatMessage> suppliedHistory = new ArrayList<>();
            if (supplied.size() > 1) {
                for (ChatMessage message : supplied.subList(0, supplied.size() - 1)) {
                    suppliedHistory.add(message.copy());
                }
            }
            List<ChatMessage> stored = completedHistory(suppliedHistory);
            if (stored.isEmpty()) stored = conversations.load(userId, sessionId);
            String callerSystem = request.has("system_message")
                    ? request.get("system_message").getAsString() : "";

            activeStage = "retrieval";
            boolean retrievalEnabled = !request.has("retrieval_enabled")
                    || request.get("retrieval_enabled").getAsBoolean();
            if (retrievalEnabled) {
                List<LocalRagStore.RetrievedPassage> retrieved =
                        Retrieval.retrieve(rag, current.content, userId, sessionId);
                rag.recordRetrieval(current.content, userId, sessionId, retrieved);
                passages = rag.fitPassages(retrieved, null);
                if (!passages.isEmpty()) {
                    JsonObject retrievalEvent = event("retrieval_context", requestId, chatId);
                    for (LocalRagStore.RetrievedPassage passage : passages) citations.add(passage.toJson());
                    retrievalEvent.add("citations", citations);
                    for (LocalRagStore.RetrievedPassage passage : passages) contextIds.add(passage.passageId);
                    retrievalEvent.add("context_ids", contextIds);
                    emit(sink, retrievalEvent);
                }
            }

            activeStage = "context_build";
            String evidence = rag.formatContext(passages, null);
            String system = joinSystem(callerSystem, systemPrompt,
                    evidence.isEmpty() ? "" : "Local evidence was retrieved for this turn. "
                            + "Treat it as supplemental guidance, not as an exact or authoritative answer. "
                            + "Start with the user's actual question and the safety rules above. "
                            + "Use retrieved content only when it directly matches the user's subject, "
                            + "population or life stage, condition, timing and requested action. "
                            + "Unrelated or incomplete passages must be ignored. Explicit symptoms in "
                            + "the user's question always take priority over retrieved text. "
                            + "Do not copy a passage just because it was retrieved. "
                            + "Discard evidence that is mismatched, incomplete, contradictory, unsafe "
                            + "or likely to hide a warning sign, and reason from the question to give "
                            + "the safer answer. Retrieved content must never override appropriate "
                            + "escalation, scope limits or honest uncertainty. Never mention retrieval, "
                            + "passages, ranking, citations or internal evidence metadata in the "
                            + "user-facing answer.");

            Set<String> selectedTools = request.has("tool_names") ? parseToolNames(request.getAsJsonArray("tool_names")) : null;
            boolean toolsEnabled = !request.has("tool_names")
                    || (selectedTools != null && !selectedTools.isEmpty());
            OfflineToolProvider tools = toolsEnabled
                    ? new OfflineToolProvider(userId, sessionId, rag.database(), assets, selectedTools)
                    : null;
            List<JsonObject> toolSchemas = tools == null ? new ArrayList<>() : tools.schemas();

            List<ChatMessage> generationTurns = RuntimePolicy.buildContext(
                    stored, system, evidence, toolSchemas, null);
            String userContent = current.content;
            if (!evidence.isEmpty()) {
                userContent += "\n\nContext for this question:\n" + evidence;
            }
            generationTurns.add(ChatMessage.user(userContent));

            activeStage = "generation";
            int toolRounds = 0;
            boolean forceAnswer = false;
            int forcedAnswerAttempts = 0;
            activeRequestId = requestId;
            activeChatId = chatId;

            while (true) {
                if (cancelled) throw new java.util.concurrent.CancellationException();
                OfflineToolProvider activeTools = forceAnswer ? null : tools;
                if (activeTools != null) activeTools.beginTurn(toolRounds + 1);
                String prompt = RuntimePolicy.renderForPrompt(generationTurns, system);
                ConversationConfig config = new ConversationConfig(
                        Contents.Companion.of(system == null ? "" : system),
                        Collections.emptyList(),
                        activeTools == null ? Collections.emptyList() : Collections.singletonList(activeTools),
                        samplerConfig(request),
                        false,
                        Collections.emptyList(),
                        Collections.emptyMap(),
                        null,
                        prefillPreface,
                        outputLimit(request),
                        new ThinkingConfig(false),
                        responseFormat(request) != null);
                conversation = engine.createConversation(config);
                activeConversation = conversation;
                
                StreamResult generated = streamWithRetries(conversation, prompt, requestId,
                        chatId, sink, activeTools, outputLimit(request), request, system, prefillPreface);
                conversation = activeConversation;
                totalGeneratedTokens += generated.tokenCount;
                JsonArray toolRequests = generated.toolRequests;

                if (toolRequests.size() > 0) {
                    JsonObject callEvent = event("tool_call_requested", requestId, chatId);
                    callEvent.add("tool_calls", toolRequests.deepCopy());
                    emit(sink, callEvent);
                    if (activeTools == null) {
                        forcedAnswerAttempts++;
                        if (forceAnswer && forcedAnswerAttempts >= 2) {
                            toolRequests = new JsonArray();
                            generated = new StreamResult(generated.text, toolRequests, generated.tokenCount);
                        } else {
                            generationTurns.add(ChatMessage.system(
                                    "Answer the user directly now. Tool use is disabled for this final response; "
                                            + "use the completed tool results already in the current turn and do not request another tool."));
                            forceAnswer = true;
                            closeConversation(conversation);
                            conversation = null;
                            activeConversation = null;
                            continue;
                        }
                    } else if (toolRounds >= RuntimePolicy.MAX_TOOL_ROUNDS) {
                        generationTurns.add(ChatMessage.system(
                                "The maximum number of local tool-call rounds has been reached. "
                                        + "Answer the user now using the completed tool results. Do not request another tool."));
                        forceAnswer = true;
                        closeConversation(conversation);
                        conversation = null;
                        activeConversation = null;
                        continue;
                    } else {
                        toolWasUsed = true;
                        toolRounds++;
                    }
                    if (toolRequests.isEmpty()) {
                        finalText = generated.text;
                        break;
                    }
                    if (activeTools == null) {
                        throw new IllegalArgumentException("tool call received when tools are disabled");
                    }
                    for (JsonElement toolRequest : toolRequests) {
                        activeTools.executeRequested(toolRequest.getAsJsonObject());
                    }
                    JsonArray toolResults = activeTools.drainCalls();
                    JsonObject resultEvent = event("tool_result", requestId, chatId);
                    resultEvent.add("tool_results", toolResults.deepCopy());
                    emit(sink, resultEvent);
                    finalText = generated.text;
                    ChatMessage toolAssistant = new ChatMessage();
                    toolAssistant.role = "assistant";
                    toolAssistant.content = generated.text.isEmpty() ? null : generated.text;
                    toolAssistant.toolCalls = toolRequests.deepCopy();
                    generationTurns.add(toolAssistant);
                    for (JsonElement resultElement : toolResults) {
                        JsonObject resultObject = resultElement.getAsJsonObject();
                        ChatMessage toolMessage = new ChatMessage();
                        toolMessage.role = "tool";
                        toolMessage.name = resultObject.get("tool").getAsString();
                        toolMessage.toolCallId = resultObject.get("call_id").getAsString();
                        toolMessage.content = resultObject.get("result").toString();
                        generationTurns.add(toolMessage);
                    }
                    closeConversation(conversation);
                    conversation = null;
                    activeConversation = null;
                    continue;
                }
                finalText = generated.text;
                break;
            }

            ChatMessage assistant = new ChatMessage();
            assistant.role = "assistant";
            assistant.content = finalText;
            conversations.append(userId, sessionId, assistant, citations);
            boolean grounded = !passages.isEmpty();
            String outcome = grounded ? "grounded_answer"
                    : toolWasUsed ? "tool_answer"
                    : retrievalEnabled ? "unsupported"
                    : "ungrounded_answer";
            conversations.recordTurn(requestId, userId, sessionId,
                    UNROUTED_SAFETY_LEVEL, UNROUTED_SAFETY_REASON,
                    outcome, finalText, contextIds, grounded);

            JsonObject completed = event("completed", requestId, chatId);
            completed.addProperty("text", finalText);
            completed.addProperty("safety_level", UNROUTED_SAFETY_LEVEL);
            completed.addProperty("grounded", grounded);
            completed.addProperty("output_tokens", totalGeneratedTokens > 0 ? totalGeneratedTokens : RuntimePolicy.count(finalText, null));
            completed.addProperty("retrieved_passage_count", passages.size());
            completed.add("context_ids", contextIds);
            completed.add("citations", citations);
            emit(sink, completed);

        } catch (java.util.concurrent.CancellationException exception) {
            conversations.recordTurn(requestId, userId, sessionId,
                    UNROUTED_SAFETY_LEVEL, UNROUTED_SAFETY_REASON,
                    "cancelled", finalText, contextIds, false);
            emit(sink, event("cancelled", requestId, chatId));
        } catch (Throwable throwable) {
            conversations.recordTurn(requestId, userId, sessionId,
                    UNROUTED_SAFETY_LEVEL, UNROUTED_SAFETY_REASON,
                    "error", finalText, contextIds, false);
            JsonObject error = event("error", requestId, chatId);
            error.addProperty("error_type", throwable.getClass().getName());
            error.addProperty("error", throwable.getMessage() == null ? throwable.toString() : throwable.getMessage());
            error.addProperty("error_stage", activeStage); // Reports exact stage where failure occurred
            emit(sink, error);
        } finally {
            Conversation active = activeConversation;
            activeConversation = null;
            activeRequestId = null;
            activeChatId = null;
            closeConversation(conversation);
            if (active != null && active != conversation) closeConversation(active);
        }
    }

    private static String joinSystem(String... parts) {
        StringBuilder result = new StringBuilder();
        for (String part : parts) {
            if (part == null || part.trim().isEmpty()) continue;
            if (result.length() > 0) result.append("\n\n");
            result.append(part.trim());
        }
        return result.toString();
    }

    public void cancel(String chatId) {
        String requestedId = chatId == null ? "" : chatId;
        if (!requestedId.isEmpty()
                && !requestedId.equals(activeChatId)
                && !requestedId.equals(activeRequestId)) {
            return;
        }
        cancelled = true;
        Conversation conversation = activeConversation;
        if (conversation != null) {
            try { conversation.cancelProcess(); } catch (Throwable ignored) {}
        }
    }

    public LocalRagStore.DocumentRecord addDocument(byte[] content, String displayName, String userId, String sessionId) {
        if (rag == null) throw new IllegalStateException("runtime is not initialized");
        return rag.ingest(content, displayName, userId, sessionId);
    }

    public void deleteDocument(String documentId, String userId, String sessionId) {
        if (rag == null) throw new IllegalStateException("runtime is not initialized");
        rag.deleteDocument(documentId, userId, sessionId);
    }

    private StreamResult stream(Conversation conversation, String prompt, String requestId,
                                String chatId, EventSink sink, OfflineToolProvider tools,
                                int outputLimit, ResponseFormat responseFormat) throws InterruptedException {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        StringBuilder output = new StringBuilder();
        JsonArray toolRequests = new JsonArray();
        int[] emittedTokens = {0};
        // Set the moment the model produces its first output (text OR a tool call).
        AtomicBoolean responseStarted = new AtomicBoolean(false);
        AtomicLong responseStartedAtNs = new AtomicLong(0);

        conversation.sendMessageAsync(prompt, new MessageCallback() {
            @Override public void onMessage(Message message) {
                if (!responseStarted.get()) {
                    responseStartedAtNs.set(System.nanoTime()); // write the time FIRST...
                    responseStarted.set(true);                  // ...then raise the flag
                }
                if (message.getToolCalls() != null) {
                    for (com.google.ai.edge.litertlm.ToolCall toolCall : message.getToolCalls()) {
                        JsonObject rawCall = toolCall.toJson$third_party_odml_litert_lm_kotlin_java_com_google_ai_edge_litertlm_litertlm_android();
                        JsonObject normalized = new JsonObject();
                        normalized.addProperty("type", "function");
                        JsonObject function = new JsonObject();
                        if (rawCall.has("id")) normalized.add("id", rawCall.get("id").deepCopy());
                        function.addProperty("name", rawCall.get("name").getAsString());
                        function.add("arguments", rawCall.get("arguments").deepCopy());
                        normalized.add("function", function);
                        toolRequests.add(normalized);
                    }
                }
                String text = message.getToolCalls() == null || message.getToolCalls().isEmpty()
                        ? message.toString() : "";
                if (!text.isEmpty()) {
                    int remaining = outputLimit - emittedTokens[0];
                    String bounded = RuntimePolicy.truncate(text, remaining, null);
                    if (!bounded.isEmpty()) {
                        synchronized (output) { output.append(bounded); }
                        emittedTokens[0] += RuntimePolicy.count(bounded, null);
                        JsonObject token = event("token", requestId, chatId);
                        token.addProperty("text", bounded);
                        emit(sink, token);
                    }
                }
            }
            @Override public void onDone() { done.countDown(); }
            @Override public void onError(Throwable throwable) { failure.set(throwable); done.countDown(); }
        }, Collections.emptyMap(), null, null, null, outputLimit,
                new ThinkingConfig(false), responseFormat);
                
        // Two-phase timeout (instead of one fixed 240 s clock):
        //   phase 1: no output yet   -> allow FIRST_TOKEN_TIMEOUT_SECONDS for the first word
        //   phase 2: output flowing  -> the clock restarts, STREAMING_BUDGET_SECONDS to finish
        final long waitBeganNs = System.nanoTime();
        boolean timedOut = false;
        while (!done.await(250, TimeUnit.MILLISECONDS)) {
            boolean started = responseStarted.get();
            long now = System.nanoTime();
            long elapsedNs = started ? now - responseStartedAtNs.get() : now - waitBeganNs;
            long limitSeconds = started ? STREAMING_BUDGET_SECONDS : FIRST_TOKEN_TIMEOUT_SECONDS;
            if (elapsedNs >= TimeUnit.SECONDS.toNanos(limitSeconds)) {
                timedOut = true;
                break;
            }
        }
        if (timedOut) {
            // Stop the model so it does not keep burning battery in the background.
            try { conversation.cancelProcess(); } catch (Throwable ignored) {}
            String partial;
            synchronized (output) { partial = output.toString(); }
            if (partial.isEmpty()) {
                throw new IllegalStateException("local generation timed out");
            }
            // Words were already streaming to the screen: KEEP them as the answer
            // instead of throwing an error that would wipe out what the person read.
            return new StreamResult(RuntimePolicy.truncate(partial, outputLimit, null),
                    new JsonArray(), emittedTokens[0]);
        }
        if (failure.get() != null) {
            boolean nothingYet;
            synchronized (output) { nothingYet = output.length() == 0; }
            if (nothingYet && toolRequests.isEmpty()) {
                throw new RetryableGenerationException(failure.get());
            }
            throw new IllegalStateException("local generation failed", failure.get());
        }
        String finalOutput;
        synchronized (output) { finalOutput = output.toString(); }
        return new StreamResult(RuntimePolicy.truncate(finalOutput, outputLimit, null), toolRequests, emittedTokens[0]);
    }

    private StreamResult streamWithRetries(Conversation conversation, String prompt,
                                           String requestId, String chatId, EventSink sink,
                                           OfflineToolProvider tools, int outputLimit,
                                           JsonObject request, String system,
                                           boolean prefillPreface) throws InterruptedException {
        int attempts = request.has("retry_attempts")
                ? Math.max(1, request.get("retry_attempts").getAsInt()) : 2;
        RetryableGenerationException last = null;
        for (int attempt = 1; attempt <= attempts; attempt++) {
            try {
                return stream(conversation, prompt, requestId, chatId, sink, tools,
                        outputLimit, responseFormat(request));
            } catch (RetryableGenerationException exception) {
                last = exception;
                if (attempt >= attempts) break;
                closeConversation(conversation);
                conversation = engine.createConversation(new ConversationConfig(
                        Contents.Companion.of(system == null ? "" : system), Collections.emptyList(),
                        tools == null ? Collections.emptyList() : Collections.singletonList(tools),
                        samplerConfig(request), false, Collections.emptyList(), Collections.emptyMap(), null,
                        prefillPreface, outputLimit, new ThinkingConfig(false),
                        responseFormat(request) != null));
                activeConversation = conversation;
            }
        }
        throw new IllegalStateException("local generation failed after retries", last);
    }

    private static int outputLimit(JsonObject request) {
        if (!request.has("generation_options") || !request.get("generation_options").isJsonObject()) {
            return RuntimePolicy.MAX_OUTPUT_TOKENS;
        }
        JsonObject options = request.getAsJsonObject("generation_options");
        JsonElement requested = options.has("max_output_tokens") ? options.get("max_output_tokens")
                : options.get("max_tokens");
        if (requested == null || !requested.isJsonPrimitive()) return RuntimePolicy.MAX_OUTPUT_TOKENS;
        try { return Math.max(1, Math.min(requested.getAsInt(), RuntimePolicy.MAX_OUTPUT_TOKENS)); }
        catch (RuntimeException ignored) { return RuntimePolicy.MAX_OUTPUT_TOKENS; }
    }

    private static SamplerConfig samplerConfig(JsonObject request) {
        if (!request.has("generation_options")
                || !request.get("generation_options").isJsonObject()) return null;
        JsonObject options = request.getAsJsonObject("generation_options");
        if (!options.has("temperature") && !options.has("top_p")
                && !options.has("top_k") && !options.has("seed")) return null;
        int topK = integerOption(options, "top_k", 40);
        double topP = numberOption(options, "top_p", 1.0);
        double temperature = numberOption(options, "temperature", 1.0);
        int seed = integerOption(options, "seed", 0);
        return new SamplerConfig(topK, topP, temperature, seed);
    }

    private static ResponseFormat responseFormat(JsonObject request) {
        if (!request.has("generation_options")
                || !request.get("generation_options").isJsonObject()) return null;
        JsonObject options = request.getAsJsonObject("generation_options");
        if (!options.has("response_format") || !options.get("response_format").isJsonObject()) return null;
        JsonObject response = options.getAsJsonObject("response_format");
        if (!"json_object".equals(string(response, "type", ""))) return null;
        JsonElement schema = response.get("schema");
        return ResponseFormat.json(schema == null ? "{}" : schema.toString());
    }

    private static int integerOption(JsonObject options, String field, int fallback) {
        try { return options.has(field) ? options.get(field).getAsInt() : fallback; }
        catch (RuntimeException ignored) { return fallback; }
    }

    private static double numberOption(JsonObject options, String field, double fallback) {
        try { return options.has(field) ? options.get(field).getAsDouble() : fallback; }
        catch (RuntimeException ignored) { return fallback; }
    }

    private static final class StreamResult {
        final String text;
        final JsonArray toolRequests;
        final int tokenCount;
        StreamResult(String text, JsonArray toolRequests, int tokenCount) {
            this.text = text;
            this.toolRequests = toolRequests;
            this.tokenCount = tokenCount;
        }
    }

    private static final class RetryableGenerationException extends RuntimeException {
        RetryableGenerationException(Throwable cause) { super(cause); }
    }

    private static List<ChatMessage> parseMessages(JsonArray array) {
        List<ChatMessage> messages = new ArrayList<>();
        if (array == null) return messages;
        for (JsonElement element : array) {
            JsonObject object = element.getAsJsonObject();
            ChatMessage message = new ChatMessage();
            message.role = object.has("role") ? object.get("role").getAsString() : "user";
            message.content = object.has("content") && !object.get("content").isJsonNull()
                    ? textContent(object.get("content")) : "";
            message.name = object.has("name") ? object.get("name").getAsString() : null;
            message.toolCallId = object.has("tool_call_id") ? object.get("tool_call_id").getAsString() : null;
            message.toolCalls = object.has("tool_calls") ? object.get("tool_calls") : null;
            messages.add(message);
        }
        return messages;
    }

    private static List<ChatMessage> completedHistory(List<ChatMessage> messages) {
        List<ChatMessage> result = new ArrayList<>();
        ChatMessage pendingUser = null;
        for (ChatMessage message : messages) {
            if ("user".equals(message.role)) {
                pendingUser = message;
            } else if ("assistant".equals(message.role)
                    && message.content != null && !message.content.isEmpty()
                    && isEmptyToolCalls(message.toolCalls) && pendingUser != null) {
                result.add(pendingUser);
                result.add(message);
                pendingUser = null;
            }
        }
        return result;
    }

    private static boolean isEmptyToolCalls(JsonElement value) {
        return value == null || value.isJsonNull()
                || (value.isJsonArray() && value.getAsJsonArray().isEmpty());
    }

    private static Set<String> parseToolNames(JsonArray array) {
        Set<String> result = new HashSet<>();
        if (array != null) for (JsonElement element : array) result.add(element.getAsString());
        return result;
    }

    private static String textContent(JsonElement content) {
        if (content.isJsonPrimitive()) return content.getAsString();
        if (!content.isJsonArray()) throw new IllegalArgumentException("the selected artifact is text-only");
        StringBuilder result = new StringBuilder();
        for (JsonElement item : content.getAsJsonArray()) {
            JsonObject part = item.getAsJsonObject();
            if (!part.has("type") || !"text".equals(part.get("type").getAsString())) {
                throw new IllegalArgumentException("the selected artifact is text-only");
            }
            result.append(part.has("text") ? part.get("text").getAsString() : "");
        }
        return result.toString();
    }

    private static JsonObject event(String type, String requestId, String chatId) {
        JsonObject result = new JsonObject();
        result.addProperty("event", type);
        result.addProperty("request_id", requestId);
        result.addProperty("chat_id", chatId);
        return result;
    }

    private static void emit(EventSink sink, JsonObject event) { if (sink != null) sink.emit(event); }

    private static String string(JsonObject object, String field, String fallback) {
        return object.has(field) && !object.get(field).isJsonNull() ? object.get(field).getAsString() : fallback;
    }

    private static String required(JsonObject object, String field) {
        String value = string(object, field, "");
        if (value.trim().isEmpty()) throw new IllegalArgumentException(field + " must not be empty");
        return value;
    }

    private String loadAsset(String name) {
        String[] candidates = { name, "prompts/" + name, "contracts/" + name };
        for (String candidate : candidates) {
            try (InputStreamReader reader = new InputStreamReader(assets.open(candidate), StandardCharsets.UTF_8)) {
                StringBuilder result = new StringBuilder();
                char[] buffer = new char[4096];
                int count;
                while ((count = reader.read(buffer)) >= 0) result.append(buffer, 0, count);
                return result.toString().trim();
            } catch (IOException ignored) { /* try next location */ }
        }
        android.util.Log.w("MamaAi", "Asset not found in any folder: " + name + " (using fallback prompt)");
        return "You are an offline maternal-health assistant. Answer safely, concisely, and do not invent facts.";
    }

    private void ensureKnowledgeFile(String knowledgePath) {
        java.io.File target = new java.io.File(knowledgePath);
        if (target.exists() && target.length() > 0) return;
        String[] candidates = { "knowledge.sqlite3", "knowledge/knowledge.sqlite3" };
        for (String candidate : candidates) {
            try (java.io.InputStream in = assets.open(candidate);
                 java.io.FileOutputStream out = new java.io.FileOutputStream(target)) {
                byte[] buf = new byte[1 << 16];
                int len;
                while ((len = in.read(buf)) > 0) {
                    out.write(buf, 0, len);
                }
                return;
            } catch (IOException ignored) { /* try next candidate */ }
        }
        android.util.Log.w("MamaAi", "Knowledge database not found in assets: " + knowledgePath);
    }
}