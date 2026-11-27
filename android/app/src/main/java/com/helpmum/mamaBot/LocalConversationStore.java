package com.helpmum.mamaBot;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import com.google.gson.JsonParser;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** SQLite conversation persistence equivalent to lib/chat/session.py. */
final class LocalConversationStore {
    private final SQLiteDatabase database;

    LocalConversationStore(SQLiteDatabase database) {
        this.database = database;
        database.execSQL("CREATE TABLE IF NOT EXISTS conversation_sessions ("
                + "user_id TEXT NOT NULL, session_id TEXT NOT NULL, model_candidate TEXT,"
                + "created_at TEXT NOT NULL, updated_at TEXT NOT NULL,"
                + "PRIMARY KEY(user_id, session_id))");
        database.execSQL("CREATE TABLE IF NOT EXISTS conversation_messages ("
                + "message_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL,"
                + "message_index INTEGER NOT NULL, role TEXT NOT NULL, message_json TEXT NOT NULL,"
                + "citations_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL)");
        database.execSQL("CREATE INDEX IF NOT EXISTS idx_conversation_messages_scope "
                + "ON conversation_messages(user_id, session_id, message_index)");
        database.execSQL("CREATE TABLE IF NOT EXISTS chat_turn_records ("
                + "turn_id TEXT PRIMARY KEY, request_id TEXT NOT NULL, user_id TEXT NOT NULL,"
                + "session_id TEXT NOT NULL, created_at TEXT NOT NULL, safety_level TEXT,"
                + "safety_reason TEXT, outcome TEXT NOT NULL, response_text TEXT,"
                + "context_ids_json TEXT NOT NULL, grounded INTEGER NOT NULL,"
                + "UNIQUE(user_id, session_id, request_id))");
        migrateNullableSafetyFields();
    }

    List<ChatMessage> load(String userId, String sessionId) {
        List<ChatMessage> result = new ArrayList<>();
        ChatMessage pendingUser = null;
        try (Cursor cursor = database.rawQuery(
                "SELECT message_json FROM conversation_messages WHERE user_id=? AND session_id=? ORDER BY message_index ASC",
                new String[]{userId, sessionId})) {
            while (cursor.moveToNext()) {
                ChatMessage message = fromJson(cursor.getString(0));
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
        }
        return result;
    }

    void append(String userId, String sessionId, ChatMessage message) {
        append(userId, sessionId, message, new JsonArray());
    }

    void append(String userId, String sessionId, ChatMessage message, JsonArray citations) {
        database.beginTransaction();
        try {
            ensureSession(userId, sessionId);
            long index = 0;
            try (Cursor cursor = database.rawQuery(
                    "SELECT COALESCE(MAX(message_index), -1) + 1 FROM conversation_messages WHERE user_id=? AND session_id=?",
                    new String[]{userId, sessionId})) {
                if (cursor.moveToFirst()) index = cursor.getLong(0);
            }
            database.execSQL("INSERT INTO conversation_messages(message_id,user_id,session_id,message_index,role,message_json,citations_json,created_at) VALUES(?,?,?,?,?,?,?,?)",
                    new Object[]{"message-" + java.util.UUID.randomUUID(), userId, sessionId, index, message.role, message.toJson().toString(), citations.toString(), Instant.now().toString()});
            database.execSQL("UPDATE conversation_sessions SET updated_at=? WHERE user_id=? AND session_id=?",
                    new Object[]{Instant.now().toString(), userId, sessionId});
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    void recordTurn(String requestId, String userId, String sessionId, String outcome, String response,
                    JsonArray contextIds, boolean grounded) {
        database.beginTransaction();
        try {
            database.execSQL("INSERT INTO chat_turn_records(turn_id,request_id,user_id,session_id,created_at,safety_level,safety_reason,outcome,response_text,context_ids_json,grounded) VALUES(?,?,?,?,?,?,?,?,?,?,?) "
                    + "ON CONFLICT(user_id,session_id,request_id) DO UPDATE SET "
                    + "outcome=excluded.outcome, response_text=excluded.response_text, "
                    + "context_ids_json=excluded.context_ids_json, grounded=excluded.grounded",
                    new Object[]{"turn-" + java.util.UUID.randomUUID(), requestId, userId, sessionId,
                            Instant.now().toString(), null, null, outcome, response,
                            contextIds.toString(), grounded ? 1 : 0});
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    private void migrateNullableSafetyFields() {
        boolean safetyLevelRequired = false;
        boolean safetyReasonRequired = false;
        try (Cursor cursor = database.rawQuery("PRAGMA table_info(chat_turn_records)", null)) {
            while (cursor.moveToNext()) {
                String name = cursor.getString(1);
                boolean required = cursor.getInt(3) != 0;
                if ("safety_level".equals(name)) safetyLevelRequired = required;
                if ("safety_reason".equals(name)) safetyReasonRequired = required;
            }
        }
        if (!safetyLevelRequired && !safetyReasonRequired) return;
        database.beginTransaction();
        try {
            database.execSQL("CREATE TABLE chat_turn_records_migrated ("
                    + "turn_id TEXT PRIMARY KEY, request_id TEXT NOT NULL, user_id TEXT NOT NULL,"
                    + "session_id TEXT NOT NULL, created_at TEXT NOT NULL, safety_level TEXT,"
                    + "safety_reason TEXT, outcome TEXT NOT NULL, response_text TEXT,"
                    + "context_ids_json TEXT NOT NULL, grounded INTEGER NOT NULL,"
                    + "UNIQUE(user_id, session_id, request_id))");
            database.execSQL("INSERT INTO chat_turn_records_migrated "
                    + "SELECT turn_id, request_id, user_id, session_id, created_at, safety_level, "
                    + "safety_reason, outcome, response_text, context_ids_json, grounded "
                    + "FROM chat_turn_records");
            database.execSQL("DROP TABLE chat_turn_records");
            database.execSQL("ALTER TABLE chat_turn_records_migrated RENAME TO chat_turn_records");
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    private void ensureSession(String userId, String sessionId) {
        String now = Instant.now().toString();
        database.execSQL("INSERT OR IGNORE INTO conversation_sessions(user_id,session_id,model_candidate,created_at,updated_at) VALUES(?,?,?,?,?)",
                new Object[]{userId, sessionId, "gemma-4-e2b-it-litert-lm", now, now});
    }

    private static ChatMessage fromJson(String value) {
        var object = JsonParser.parseString(value).getAsJsonObject();
        ChatMessage message = new ChatMessage();
        message.role = object.has("role") ? object.get("role").getAsString() : "user";
        message.content = object.has("content") && !object.get("content").isJsonNull()
                ? object.get("content").getAsString() : null;
        message.name = object.has("name") ? object.get("name").getAsString() : null;
        message.toolCallId = object.has("tool_call_id") ? object.get("tool_call_id").getAsString() : null;
        message.toolCalls = object.has("tool_calls") ? object.get("tool_calls") : null;
        return message;
    }

    private static boolean isEmptyToolCalls(JsonElement value) {
        return value == null || value.isJsonNull()
                || (value.isJsonArray() && value.getAsJsonArray().isEmpty());
    }
}
