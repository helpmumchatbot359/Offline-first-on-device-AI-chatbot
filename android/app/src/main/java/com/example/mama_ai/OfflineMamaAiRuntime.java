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

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
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
   
    private static final long FIRST_TOKEN_TIMEOUT_SECONDS = 240; // 4 minutes
    
    private static final long STREAMING_BUDGET_SECONDS = 180; // 3 minutes


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

   public void generate(JsonObject request, EventSink sink) {
        if (engine == null || rag == null) throw new IllegalStateException("runtime is not initialized");
        cancelled = false;
        String requestId = string(request, "request_id", "request-" + System.nanoTime());
        String userId = required(request, "user_id");
        String sessionId = required(request, "session_id");
        String chatId = string(request, "chat_id", sessionId);

        int totalGeneratedTokens = 0;
        String activeStage = "history_loading";
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

        activeStage = "system_prompt_building";
        String callerSystem = request.has("system_message")
                ? request.get("system_message").getAsString() : "";
        String system = joinSystem(callerSystem, systemPrompt);
        OfflineToolProvider tools = new OfflineToolProvider(
                userId, sessionId, current.content, rag, assets);
        List<JsonObject> toolSchemas = tools == null ? new ArrayList<>() : tools.schemas();
        Conversation conversation = null;
        String finalText = "";
        boolean toolWasUsed = false;
        List<LocalRagStore.RetrievedPassage> passages = new ArrayList<>();
        JsonArray contextIds = new JsonArray();
        activeRequestId = requestId;
        activeChatId = chatId;

        activeStage = "generation";
        try {
            List<ChatMessage> generationTurns = RuntimePolicy.buildContext(
                    stored, system, toolSchemas, null);
            generationTurns.add(ChatMessage.user(current.content));
            int toolRounds = 0;
            boolean toolsDisabled = false;
            while (true) {
                if (cancelled) throw new java.util.concurrent.CancellationException();
                if (toolRounds >= RuntimePolicy.MAX_TOOL_ROUNDS) toolsDisabled = true;
                OfflineToolProvider activeTools = toolsDisabled ? null : tools;
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
                    activeStage = "tool_calls";
                    JsonObject callEvent = event("tool_call_requested", requestId, chatId);
                    callEvent.add("tool_calls", toolRequests.deepCopy());
                    emit(sink, callEvent);
                    if (activeTools == null) {
                        throw new IllegalStateException(
                                "model returned a tool call after tool schemas were removed");
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
                    List<LocalRagStore.RetrievedPassage> retrievedPassages =
                            activeTools.drainRetrievalPassages();
                    if (!retrievedPassages.isEmpty()) {
                        activeStage = "retrieval_context";
                        passages = retrievedPassages;
                        contextIds = new JsonArray();
                        JsonObject retrievalEvent = event("retrieval_context", requestId, chatId);
                        JsonArray citations = new JsonArray();
                        for (LocalRagStore.RetrievedPassage passage : passages) {
                            citations.add(passage.toJson());
                            contextIds.add(passage.passageId);
                        }
                        retrievalEvent.add("citations", citations);
                        retrievalEvent.add("context_ids", contextIds.deepCopy());
                        emit(sink, retrievalEvent);
                    }
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
            activeStage = "assistant_message"
            assistant.role = "assistant";
            assistant.content = finalText;
            JsonArray citations = new JsonArray();
            for (LocalRagStore.RetrievedPassage passage : passages) {
                citations.add(passage.toJson());
            }
            conversations.append(userId, sessionId, assistant, citations);
            boolean grounded = !passages.isEmpty();
            String outcome = grounded ? "grounded_answer"
                    : toolWasUsed ? "tool_answer"
                    : "ungrounded_answer";
            conversations.recordTurn(requestId, userId, sessionId,
                    outcome, finalText, contextIds, grounded);
            JsonObject completed = event("completed", requestId, chatId);
            completed.addProperty("text", finalText);
            completed.addProperty("grounded", grounded);
            completed.add("context_ids", contextIds);
            completed.add("citations", citations);
            emit(sink, completed);
        } catch (java.util.concurrent.CancellationException exception) {
            conversations.recordTurn(requestId, userId, sessionId,
                    "cancelled", finalText, contextIds, false);
            emit(sink, event("cancelled", requestId, chatId));
        } catch (Throwable throwable) {
            conversations.recordTurn(requestId, userId, sessionId,
                    "error", finalText, contextIds, false);
            JsonObject error = event("error", requestId, chatId);
            error.addProperty("error_type", throwable.getClass().getName());
            error.addProperty("error", throwable.getMessage() == null ? throwable.toString()
             : throwable.getMessage());
            error.addProperty("error_stage", activeStage);
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
        AtomicBoolean responseStarted = new AtomicBoolean(false);
        AtomicLong responseStartedAtNs = new AtomicLong();
        StringBuilder output = new StringBuilder();
        JsonArray toolRequests = new JsonArray();
        int[] emittedTokens = {0};

        conversation.sendMessageAsync(prompt, new MessageCallback() {
            @Override public void onMessage(Message message) {
                if (!responseStarted.get()) {
                    responseStartedAtNs.set(System.nanoTime()); // write the time FIRST...
                    responseStarted.set(true);                  // ...then raise the flag
                }
                if (message.getToolCalls() != null) {
                    for (com.google.ai.edge.litertlm.ToolCall toolCall : message.getToolCalls()) {
                        JsonObject rawCall = toolCall.toJson$third_party_odml_litert_lm_kotlin_java_com_google_ai_edge_litertlm_litertlm_android();
                        JsonObject rawFunction = rawCall.has("function")
                                && rawCall.get("function").isJsonObject()
                                ? rawCall.getAsJsonObject("function") : rawCall;
                        JsonObject normalized = new JsonObject();
                        normalized.addProperty("type", "function");
                        JsonObject function = new JsonObject();
                        if (rawCall.has("id")) normalized.add("id", rawCall.get("id").deepCopy());
                        JsonElement rawName = rawFunction.get("name");
                        JsonElement rawArguments = rawFunction.get("arguments");
                        if (rawName == null || rawName.isJsonNull()
                                || rawArguments == null || rawArguments.isJsonNull()) {
                            throw new IllegalArgumentException("LiteRT returned an incomplete tool call");
                        }
                        function.addProperty("name", rawName.getAsString());
                        function.add("arguments", rawArguments.deepCopy());
                        normalized.add("function", function);
                        synchronized (output) {
                            toolRequests.add(normalized);
                        }
                    }
                }
                String text = message.getToolCalls() == null || message.getToolCalls().isEmpty()
                        ? message.toString() : "";
                if (!text.isEmpty()) {
                    int remaining = outputLimit - emittedTokens[0];
                    String bounded = RuntimePolicy.truncate(text, remaining, null);
                    if (!bounded.isEmpty()) {
                        synchronized (output) {
                            output.append(bounded);
                            emittedTokens[0] += RuntimePolicy.count(bounded, null);
                        }

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

        final long waitBeganNs = System.nanoTime();
        boolean timedOut = false;
        while (!done.await(250, TimeUnit.MILLISECONDS)) {
            boolean started = responseStarted.get();
            long now = System.nanoTime();
            long elapsedNs = started ? now - responseStartedAtNs.get() : now - waitBeganNs;
            long limitSeconds = started
                    ? RuntimePolicy.STREAMING_BUDGET_SECONDS
                    : RuntimePolicy.FIRST_TOKEN_TIMEOUT_SECONDS;
            if (elapsedNs >= TimeUnit.SECONDS.toNanos(limitSeconds)) {
                timedOut = true;
                break;
            }
        }
        if (timedOut) {
            try { conversation.cancelProcess(); } catch (Throwable ignored) {}
            String partial;
            synchronized (output) { partial = output.toString(); }
            if (partial.isEmpty()) {
                throw new IllegalStateException("local generation timed out");
            }
            return new StreamResult(
                    RuntimePolicy.truncate(partial, outputLimit, null),
                    toolRequests, emittedTokens[0]);
        }
        if (failure.get() != null) {
            boolean nothingYet;
            synchronized (output) {
                nothingYet = output.length() == 0 && toolRequests.isEmpty();
            }
            if (nothingYet) {
                throw new RetryableGenerationException(failure.get());
            }
            throw new IllegalStateException("local generation failed", failure.get());
        }
        String finalOutput;
        synchronized (output) { finalOutput = output.toString(); }
        return new StreamResult(
                RuntimePolicy.truncate(finalOutput, outputLimit, null),
                toolRequests, emittedTokens[0]);
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
        android.util.Log.w("MamaAi", "Asset not found in any folder: " + name);
        throw new IllegalStateException(
            "Required asset not found in any location: " + name);
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