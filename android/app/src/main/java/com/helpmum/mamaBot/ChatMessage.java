package com.helpmum.mamaBot;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

/** Runtime message shape shared by Flutter and the local inference bridge. */
final class ChatMessage {
    String role;
    String content;
    String name;
    String toolCallId;
    JsonElement toolCalls;

    static ChatMessage system(String content) {
        ChatMessage message = new ChatMessage();
        message.role = "system";
        message.content = content;
        return message;
    }

    static ChatMessage user(String content) {
        ChatMessage message = new ChatMessage();
        message.role = "user";
        message.content = content;
        return message;
    }

    ChatMessage copy() {
        ChatMessage copy = new ChatMessage();
        copy.role = role;
        copy.content = content;
        copy.name = name;
        copy.toolCallId = toolCallId;
        copy.toolCalls = toolCalls == null ? null : toolCalls.deepCopy();
        return copy;
    }

    JsonObject toJson() {
        JsonObject result = new JsonObject();
        if (role != null) result.addProperty("role", role);
        if (content != null) result.addProperty("content", content);
        if (name != null) result.addProperty("name", name);
        if (toolCallId != null) result.addProperty("tool_call_id", toolCallId);
        if (toolCalls != null) result.add("tool_calls", toolCalls.deepCopy());
        return result;
    }
}
