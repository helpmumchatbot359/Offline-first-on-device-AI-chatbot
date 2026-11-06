package com.example.mama_ai;

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
    static final int MAX_CONTEXT_TOKENS = 4096;           // was 4096; halves KV cache
    static final int MAX_HISTORY_TOKENS = 3072;            // was 3072
    static final int MAX_HISTORY_TURNS = 3;               // was 5
    // The newest complete turn is mandatory: it may use the whole context room
    // and is never dropped, even when the token budget is exhausted. Older
    // turns are optional and are fitted into whatever room remains.
    static final int MIN_NEWEST_TURN_TOKENS = 96;
    static final int MIN_OLDER_TURN_TOKENS = 48;
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

    /**
     * Selects the newest complete user/assistant pairs that fit the budget.
     *
     * The newest pair is MANDATORY: it is always returned, and only its answer
     * is shortened (then its question) when it does not fit. This is what makes
     * an offline question such as "what was my last question?" answerable, even
     * when the last turn came from the online assistant and its answer is long.
     *
     * Older pairs are optional. They are added newest-first while
     * {@code maxTurns} and {@code maxTokens} allow it. Each older answer is
     * shortened to its fair share of the remaining room, so one long answer
     * cannot push out the other recent turns.
     */
    static List<ChatMessage> selectRecentHistory(
            List<ChatMessage> ordered,
            int maxTokens,
            int maxTurns,
            TokenCounter counter) {
        if (ordered == null || ordered.isEmpty() || maxTurns <= 0) {
            return Collections.emptyList();
        }
        List<List<ChatMessage>> pairs = completePairs(ordered);
        if (pairs.isEmpty()) return Collections.emptyList();

        List<List<ChatMessage>> selected = new ArrayList<>();
        int used = 0;

        // 1. Newest pair: always kept. It is not subject to MAX_HISTORY_TOKENS;
        //    its only limit is the room left after the system prompt and output
        //    reserve. A small floor guarantees it survives a zero budget.
        int newestBudget = Math.max(maxTokens, MIN_NEWEST_TURN_TOKENS);
        List<ChatMessage> newest = fitPair(pairs.get(pairs.size() - 1), newestBudget, counter);
        if (!newest.isEmpty()) {
            selected.add(newest);
            used += pairSize(newest, counter);
        }

        // 2. Older pairs: optional. MAX_HISTORY_TOKENS is the cap for the
        //    optional part of the history.
        int optionalLimit = Math.min(maxTokens, MAX_HISTORY_TOKENS);
        for (int index = pairs.size() - 2; index >= 0 && selected.size() < maxTurns; index--) {
            int remaining = optionalLimit - used;
            int slots = Math.max(1, maxTurns - selected.size());
            if (remaining < MIN_OLDER_TURN_TOKENS) break;

            int pairBudget = Math.max(MIN_OLDER_TURN_TOKENS, remaining / slots);
            List<ChatMessage> fitted = fitPair(pairs.get(index), pairBudget, counter);
            if (fitted.isEmpty()) break;

            selected.add(fitted);
            used += pairSize(fitted, counter);
        }

        Collections.reverse(selected);
        List<ChatMessage> result = new ArrayList<>();
        for (List<ChatMessage> pair : selected) result.addAll(pair);
        return result;
    }

    /** Complete user -> assistant pairs, oldest first. */
    private static List<List<ChatMessage>> completePairs(List<ChatMessage> ordered) {
        List<List<ChatMessage>> pairs = new ArrayList<>();
        ChatMessage pendingUser = null;
        for (ChatMessage message : ordered) {
            if (message == null || message.role == null) continue;
            if ("user".equals(message.role)) {
                pendingUser = message;
            } else if ("assistant".equals(message.role)
                    && message.content != null && !message.content.isEmpty()
                    && !hasToolCalls(message)
                    && pendingUser != null) {
                List<ChatMessage> pair = new ArrayList<>(2);
                pair.add(pendingUser);
                pair.add(message);
                pairs.add(pair);
                pendingUser = null;
            }
            // Incomplete turns (a failed answer, a tool-only sequence or a new
            // question that replaced an unanswered one) are never paired.
        }
        return pairs;
    }

    private static boolean hasToolCalls(ChatMessage message) {
        return message.toolCalls != null && !message.toolCalls.isJsonNull()
                && (!message.toolCalls.isJsonArray()
                    || !message.toolCalls.getAsJsonArray().isEmpty());
    }

    private static List<ChatMessage> fitPair(
            List<ChatMessage> pair,
            int maxTokens,
            TokenCounter counter) {
        if (pair == null || pair.size() < 2 || maxTokens <= 0) {
            return Collections.emptyList();
        }
        ChatMessage question = pair.get(0).copy();
        ChatMessage answer = pair.get(1).copy();
        List<ChatMessage> fitted = new ArrayList<>(2);
        fitted.add(question);
        fitted.add(answer);
        if (pairSize(fitted, counter) <= maxTokens) return fitted;

        int contentBudget = maxTokens - overhead(question, counter) - overhead(answer, counter);
        if (contentBudget <= 0) return Collections.emptyList();

        // The question is what makes "what was my last question?" answerable,
        // so the answer gives up its room first.
        int questionTokens = count(question.content, counter);
        if (questionTokens >= contentBudget) {
            question.content = truncate(question.content, contentBudget, counter);
            answer.content = "";
        } else {
            answer.content = truncate(answer.content, contentBudget - questionTokens, counter);
        }

        // JSON escaping and the message wrapper add bytes the plain text count
        // cannot see. Shrink until the encoded pair really fits.
        while (pairSize(fitted, counter) > maxTokens) {
            if (answer.content != null && !answer.content.isEmpty()) {
                answer.content = truncate(answer.content, Math.max(0, count(answer.content, counter) - 1), counter);
            } else if (question.content != null && !question.content.isEmpty()) {
                question.content = truncate(question.content, Math.max(0, count(question.content, counter) - 1), counter);
            } else {
                return Collections.emptyList();
            }
        }
        return fitted;
    }

    private static int pairSize(List<ChatMessage> pair, TokenCounter counter) {
        int size = 0;
        for (ChatMessage message : pair) size += messageSize(message, counter);
        return size;
    }

    private static int messageSize(ChatMessage message, TokenCounter counter) {
        return count(message.toJson().toString(), counter);
    }

    private static int overhead(ChatMessage message, TokenCounter counter) {
        ChatMessage empty = message.copy();
        empty.content = "";
        return messageSize(empty, counter);
    }

    static List<ChatMessage> buildContext(
            List<ChatMessage> stored,
            String system,
            List<JsonObject> toolSchemas,
            TokenCounter counter) {
        // Fixed costs are reserved FIRST. The system prompt and tool schemas are
        // always sent, whatever the history budget is; only what remains after
        // the output reserve can be used for conversation turns.
        int systemTokens = count(system == null ? "" : system, counter);
        int toolTokens = count(toolSchemas == null ? "" : toolSchemas.toString(), counter);
        int roomForHistory = Math.max(
                0, MAX_CONTEXT_TOKENS - MAX_OUTPUT_TOKENS - systemTokens - toolTokens);
        List<ChatMessage> history = selectRecentHistory(
                stored, roomForHistory, MAX_HISTORY_TURNS, counter);
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