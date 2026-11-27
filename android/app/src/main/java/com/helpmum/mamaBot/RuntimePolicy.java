package com.helpmum.mamaBot;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * The bounded-context policy ported from lib/chat/context_manager.py.
 *
 * The LiteRT-LM Java API does not expose the Gemma tokenizer through the
 * public Android surface used by this project, so the default counter uses
 * the same conservative fallback as the Python implementation. The counter
 * is injectable when the product bridge exposes the native tokenizer.
 */
final class RuntimePolicy {
    static final int MAX_CONTEXT_TOKENS = 2048;           // was 4096; halves KV cache
    static final int MAX_HISTORY_TOKENS = 768;            // was 3072
    static final int MAX_HISTORY_TURNS = 3;               // was 5
    static final int MAX_INPUT_TOKENS = 1024;              // was 1024
    static final int MAX_OUTPUT_TOKENS = 512;             // was 512; also caps generation time
    static final int MAX_TOOL_ROUNDS = 2;                 // was 3
    static final int MAX_TOOL_ARGUMENT_TOKENS = 256;      // was 1024
    static final int MAX_RETRIEVED_PASSAGES = 2;          // was 3
    static final int MAX_RETRIEVED_CONTEXT_TOKENS = 400;  // was 1024
    static final int FIRST_TOKEN_TIMEOUT_SECONDS = 120;
    static final int STREAMING_BUDGET_SECONDS = 120;

    interface TokenCounter {
        int count(String text);
    }

    static final TokenCounter FALLBACK_COUNTER = text -> {
        if (text == null || text.isEmpty()) return 0;
        return Math.max(1, (text.length() + 2) / 3);
    };

    private RuntimePolicy() {}

    static int count(String text, TokenCounter counter) {
        return Math.max(0, (counter == null ? FALLBACK_COUNTER : counter).count(text == null ? "" : text));
    }

    static String truncate(String text, int maxTokens, TokenCounter counter) {
        if (text == null || text.isEmpty() || maxTokens <= 0) return "";
        if (count(text, counter) <= maxTokens) return text;
        int low = 0;
        int high = text.length();
        String best = "";
        while (low <= high) {
            int middle = (low + high) >>> 1;
            String candidate = text.substring(0, middle);
            if (count(candidate, counter) <= maxTokens) {
                best = candidate;
                low = middle + 1;
            } else {
                high = middle - 1;
            }
        }
        return best.trim();
    }

    static List<ChatMessage> selectRecentHistory(
            List<ChatMessage> ordered,
            TokenCounter counter) {
        return selectRecentHistory(ordered, MAX_HISTORY_TOKENS, MAX_HISTORY_TURNS, counter);
    }

    static List<ChatMessage> selectRecentHistory(
            List<ChatMessage> ordered,
            int maxTokens,
            int maxTurns,
            TokenCounter counter) {
        if (ordered == null || ordered.isEmpty()) return Collections.emptyList();
        List<ChatMessage> selected = new ArrayList<>();
        int used = 0;
        int turns = 0;
        for (int index = ordered.size() - 1; index >= 0; index--) {
            ChatMessage message = ordered.get(index);
            if (turns >= maxTurns) break;
            int size = count(message.toJson().toString(), counter);
            if (!selected.isEmpty() && used + size > maxTokens) break;
            if (selected.isEmpty() && size > maxTokens) {
                ChatMessage shortened = message.copy();
                shortened.content = truncate(message.content, maxTokens, counter);
                selected.add(shortened);
                break;
            }
            selected.add(message.copy());
            used += size;
            if ("user".equals(message.role)) turns++;
        }
        Collections.reverse(selected);
        while (!selected.isEmpty() && !"user".equals(selected.get(0).role)) {
            selected.remove(0);
        }
        return selected;
    }

    static List<ChatMessage> buildContext(
            List<ChatMessage> stored,
            String system,
            List<JsonObject> toolSchemas,
            TokenCounter counter) {
        String fixed = (system == null ? "" : system)
                + (toolSchemas == null ? "" : toolSchemas.toString());
        int available = Math.max(0, MAX_CONTEXT_TOKENS - MAX_OUTPUT_TOKENS - count(fixed, counter));
        available = Math.min(available, MAX_HISTORY_TOKENS);
        List<ChatMessage> history = selectRecentHistory(
                stored, available, MAX_HISTORY_TURNS, counter);
        List<ChatMessage> result = new ArrayList<>();
        for (ChatMessage message : history) result.add(message.copy());
        if (system != null && !system.isEmpty()) {
            result.add(0, ChatMessage.system(system));
        }
        return result;
    }

    static String renderForPrompt(List<ChatMessage> messages) {
        return renderForPrompt(messages, null);
    }

    static String renderForPrompt(List<ChatMessage> messages, String excludedSystem) {
        StringBuilder output = new StringBuilder();
        for (ChatMessage message : messages) {
            if (excludedSystem != null && "system".equals(message.role)
                    && excludedSystem.equals(message.content)) continue;
            if (output.length() > 0) output.append("\n\n");
            String role = message.role == null ? "user" : message.role;
            output.append(role.substring(0, 1).toUpperCase()).append(role.substring(1)).append(": ");
            output.append(message.content == null ? "" : message.content);
        }
        output.append("\n\nAssistant:");
        return output.toString();
    }
}

