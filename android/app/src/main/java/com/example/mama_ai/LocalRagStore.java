package com.example.mama_ai;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import androidx.sqlite.SQLiteConnection;
import androidx.sqlite.SQLiteStatement;
import androidx.sqlite.driver.bundled.BundledSQLiteDriver;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

/** Local static-knowledge and user-document retrieval port. */
final class LocalRagStore implements AutoCloseable {
    private static final Set<String> STOPWORDS = new HashSet<>(Arrays.asList(
            "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can",
            "could", "did", "do", "does", "for", "from", "had", "has", "have", "how",
            "i", "if", "in", "is", "it", "me", "my", "no", "not", "of", "on", "or",
            "our", "should", "so", "that", "the", "their", "them", "they", "this", "to",
            "was", "we", "were", "what", "when", "where", "which", "who", "will", "with",
            "you", "your", "am", "first", "started", "start", "now", "just", "still",
            "feel", "feeling", "want", "need", "know", "tell", "please", "got", "get",
            "getting", "live", "living", "common"));
    private static final double PHRASE_COVERAGE = 0.60;
    private static final double TERM_COVERAGE = 0.70;

    private final SQLiteConnection knowledge;
    private final SQLiteDatabase runtime;
    private final SQLiteConnection runtimeSearch;
    private final Context context;
    private boolean documentFtsAvailable;
    private final boolean clinicalMetadataAvailable;

    LocalRagStore(Context context, String knowledgePath, String runtimePath) {
        this.context = context;
        knowledge = new BundledSQLiteDriver().open(knowledgePath);
        clinicalMetadataAvailable = hasKnowledgeColumn("topic");
        runtime = SQLiteDatabase.openOrCreateDatabase(runtimePath, null);
        createRuntimeTables();
        runtimeSearch = new BundledSQLiteDriver().open(runtimePath);
        createDocumentSearchIndex();
    }

    private boolean hasKnowledgeColumn(String column) {
        try (SQLiteStatement statement = knowledge.prepare("PRAGMA table_info(passages)")) {
            while (statement.step()) {
                if (column.equals(statement.getText(1))) return true;
            }
        }
        return false;
    }

    private void createRuntimeTables() {
        runtime.execSQL("CREATE TABLE IF NOT EXISTS documents ("
                + "document_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL,"
                + "display_name TEXT NOT NULL, content_hash TEXT NOT NULL, created_at TEXT NOT NULL,"
                + "character_count INTEGER NOT NULL)");
        runtime.execSQL("CREATE TABLE IF NOT EXISTS document_passages ("
                + "passage_id TEXT PRIMARY KEY, document_id TEXT NOT NULL, user_id TEXT NOT NULL,"
                + "session_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, text TEXT NOT NULL)");
        runtime.execSQL("CREATE TABLE IF NOT EXISTS health_records ("
                + "record_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL,"
                + "record_type TEXT NOT NULL, recorded_at TEXT NOT NULL, record_json TEXT NOT NULL,"
                + "created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)");
        runtime.execSQL("CREATE INDEX IF NOT EXISTS idx_health_records_scope "
                + "ON health_records(user_id, session_id, recorded_at)");
        runtime.execSQL("CREATE TABLE IF NOT EXISTS reminders ("
                + "reminder_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL,"
                + "title TEXT NOT NULL, due_at TEXT NOT NULL, category TEXT NOT NULL, notes TEXT,"
                + "recurrence TEXT, status TEXT NOT NULL DEFAULT 'scheduled',"
                + "created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)");
        runtime.execSQL("CREATE INDEX IF NOT EXISTS idx_reminders_scope "
                + "ON reminders(user_id, session_id, due_at, status)");
        runtime.execSQL("CREATE TABLE IF NOT EXISTS retrieval_runs ("
                + "retrieval_run_id TEXT PRIMARY KEY, created_at TEXT NOT NULL, query TEXT NOT NULL,"
                + "user_id TEXT NOT NULL, session_id TEXT NOT NULL, passage_ids_json TEXT NOT NULL)");
        runtime.execSQL("CREATE TABLE IF NOT EXISTS retrieval_records ("
                + "retrieval_id TEXT PRIMARY KEY, retrieval_run_id TEXT, created_at TEXT NOT NULL,"
                + "query TEXT NOT NULL, user_id TEXT NOT NULL, session_id TEXT NOT NULL,"
                + "source_type TEXT NOT NULL, passage_id TEXT NOT NULL, text TEXT NOT NULL,"
                + "score REAL NOT NULL, document_id TEXT, display_name TEXT, chunk_index INTEGER)");
        runtime.execSQL("CREATE INDEX IF NOT EXISTS idx_retrieval_records_scope "
                + "ON retrieval_records(user_id, session_id, created_at)");
    }

    private void createDocumentSearchIndex() {
        try {
            try (SQLiteStatement statement = runtimeSearch.prepare(
                    "CREATE VIRTUAL TABLE IF NOT EXISTS document_search USING fts5("
                            + "text, content='document_passages', content_rowid='rowid')")) {
                statement.step();
            }
            documentFtsAvailable = true;
        } catch (RuntimeException exception) {
            documentFtsAvailable = false;
        }
    }

    List<RetrievedPassage> retrieve(String query, String userId, String sessionId, int requestedLimit) {
        int limit = Math.min(Math.max(requestedLimit, 1), RuntimePolicy.MAX_RETRIEVED_PASSAGES);
        return retrieveInternal(query, userId, sessionId, limit);
    }

    List<RetrievedPassage> retrieveForEvaluation(String query, int requestedLimit) {
        int limit = Math.min(Math.max(requestedLimit, 1), 10);
        return retrieveInternal(query, null, null, limit);
    }

    List<RetrievedPassage> retrieveCandidates(
            String query, String userId, String sessionId, int requestedLimit) {
        int limit = Math.min(Math.max(requestedLimit, 1), 12);
        return retrieveInternal(query, userId, sessionId, limit, false);
    }

    private List<RetrievedPassage> retrieveInternal(
            String query, String userId, String sessionId, int limit) {
        return retrieveInternal(query, userId, sessionId, limit, true);
    }

    private List<RetrievedPassage> retrieveInternal(
            String query, String userId, String sessionId, int limit, boolean relevanceGate) {
        List<String> terms = terms(query);
        if (terms.size() < 2) return new ArrayList<>();
        List<RetrievedPassage> result = new ArrayList<>();
        String match = buildMatchQuery(query);
        result.addAll(searchStatic(match, terms, limit, relevanceGate));
        if (documentFtsAvailable && userId != null && sessionId != null) {
            result.addAll(searchDocuments(match, terms, userId, sessionId, limit));
        }
        result.sort((left, right) -> Double.compare(right.score, left.score));
        if (result.size() > limit) {
            return new ArrayList<>(result.subList(0, limit));
        }
        return result;
    }

    void recordRetrieval(String query, String userId, String sessionId,
                         List<RetrievedPassage> passages) {
        String createdAt = Instant.now().toString();
        String runId = "retrieval-run-" + UUID.randomUUID();
        JsonArray passageIds = new JsonArray();
        for (RetrievedPassage passage : passages) passageIds.add(passage.passageId);
        runtime.beginTransaction();
        try {
            runtime.execSQL("INSERT INTO retrieval_runs(retrieval_run_id,created_at,query,user_id,session_id,passage_ids_json) VALUES(?,?,?,?,?,?)",
                    new Object[]{runId, createdAt, query, userId, sessionId, passageIds.toString()});
            for (RetrievedPassage passage : passages) {
                runtime.execSQL("INSERT INTO retrieval_records(retrieval_id,retrieval_run_id,created_at,query,user_id,session_id,source_type,passage_id,text,score,document_id,display_name,chunk_index) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        new Object[]{"retrieval-" + UUID.randomUUID(), runId, createdAt, query,
                                userId, sessionId, passage.sourceType, passage.passageId, passage.text,
                                passage.score, passage.documentId, passage.displayName, passage.chunkIndex});
            }
            runtime.setTransactionSuccessful();
        } finally {
            runtime.endTransaction();
        }
    }

    private List<RetrievedPassage> searchStatic(
            String match, List<String> terms, int limit, boolean relevanceGate) {
        List<RetrievedPassage> result = new ArrayList<>();
        String metadata = clinicalMetadataAvailable
                ? ", passages.life_stage, passages.topic, passages.timing, passages.population, "
                + "passages.country_scope, passages.warning_signs, passages.action_boundary, passages.safety_level " : "";
        String sql = "SELECT passages.passage_id, passage_search.question, "
                + "passage_search.answer, bm25(passage_search)" + metadata
                + " FROM passage_search JOIN passages "
                + "ON passages.rowid = passage_search.rowid "
                + "WHERE passage_search MATCH ? "
                + "ORDER BY passage_search.rank LIMIT ?";
        int candidateLimit = Math.max(limit * 20, 40);
        List<SearchHit> hits = new ArrayList<>(candidateLimit);
        try (SQLiteStatement statement = knowledge.prepare(sql)) {
            statement.bindText(1, match);
            statement.bindLong(2, candidateLimit);
            while (statement.step()) {
                hits.add(new SearchHit(statement.getText(0), statement.getText(1),
                        statement.getText(2), -statement.getDouble(3),
                        clinicalMetadataAvailable ? statement.getText(4) : null,
                        clinicalMetadataAvailable ? statement.getText(5) : null,
                        clinicalMetadataAvailable ? statement.getText(6) : null,
                        clinicalMetadataAvailable ? statement.getText(7) : null,
                        clinicalMetadataAvailable ? statement.getText(8) : null,
                        clinicalMetadataAvailable ? statement.getText(9) : null,
                        clinicalMetadataAvailable ? statement.getText(10) : null,
                        clinicalMetadataAvailable ? statement.getText(11) : null));
            }
        }
        addStaticCandidates(result, hits, terms, relevanceGate);
        result.sort((left, right) -> Double.compare(right.score, left.score));
        return result.size() > limit ? new ArrayList<>(result.subList(0, limit)) : result;
    }

    private static void addStaticCandidates(List<RetrievedPassage> result,
                                             List<SearchHit> hits,
                                             List<String> queryTerms,
                                             boolean relevanceGate) {
        if (queryTerms.size() < 2) return;
        List<Candidate> candidates = new ArrayList<>();
        for (SearchHit hit : hits) {
            String question = hit.question;
            String answer = hit.answer;
            List<String> passageTerms = terms(question + " " + answer);
            int matched = 0;
            for (String term : queryTerms) if (passageTerms.contains(term)) matched++;
            double coverage = (double) matched / queryTerms.size();
            candidates.add(new Candidate(
                    coverage, phraseHits(queryTerms, terms(question)),
                    phraseHits(queryTerms, terms(answer)), passageTerms,
                    hit.passageId, answer, -hit.matchScore, question,
                    hit.lifeStage, hit.topic, hit.timing, hit.population,
                    hit.countryScope, hit.warningSigns, hit.actionBoundary, hit.safetyLevel));
        }
        boolean hasQuestionPhrase = false;
        for (Candidate candidate : candidates) {
            if (candidate.questionPhrases > 0 && candidate.coverage >= PHRASE_COVERAGE) {
                hasQuestionPhrase = true;
                break;
            }
        }
        boolean hasPhraseCandidate = false;
        for (Candidate candidate : candidates) {
            int phrases = hasQuestionPhrase ? candidate.questionPhrases : candidate.answerPhrases;
            if (phrases > 0 && candidate.coverage >= PHRASE_COVERAGE) {
                hasPhraseCandidate = true;
                break;
            }
        }
        for (Candidate candidate : candidates) {
            int phrases = hasQuestionPhrase ? candidate.questionPhrases : candidate.answerPhrases;
            boolean accepted = !relevanceGate
                    || (hasPhraseCandidate
                    ? phrases > 0 && candidate.coverage >= PHRASE_COVERAGE
                    : candidate.coverage >= TERM_COVERAGE);
            if (accepted) {
                result.add(new RetrievedPassage("internal_qa", candidate.passageId,
                        candidate.answer, candidate.coverage * 100.0
                        + candidate.questionPhrases * 30.0
                        + candidate.answerPhrases * 15.0
                        - candidate.ftsRank, candidate.question, candidate.lifeStage,
                        candidate.topic, candidate.timing, candidate.population,
                        candidate.countryScope, candidate.warningSigns, candidate.actionBoundary, candidate.safetyLevel,
                        null, null, null, null, null));
            }
        }
    }

    private List<RetrievedPassage> searchDocuments(
            String match, List<String> terms, String userId, String sessionId, int limit) {
        List<RetrievedPassage> result = new ArrayList<>();
        String sql = "SELECT document_passages.passage_id, document_passages.text, "
                + "document_passages.document_id, document_passages.chunk_index, documents.display_name "
                + "FROM document_search JOIN document_passages "
                + "ON document_passages.rowid = document_search.rowid "
                + "JOIN documents ON documents.document_id = document_passages.document_id "
                + "WHERE document_search MATCH ? AND document_passages.user_id = ? "
                + "AND document_passages.session_id = ? ORDER BY document_search.rank LIMIT ?";
        try (SQLiteStatement statement = runtimeSearch.prepare(sql)) {
            statement.bindText(1, match);
            statement.bindText(2, userId);
            statement.bindText(3, sessionId);
            statement.bindLong(4, limit);
            while (statement.step()) {
                String text = statement.getText(1);
                result.add(new RetrievedPassage(
                        "user_document", statement.getText(0), text,
                        relevance(terms, text), statement.getText(2), statement.getText(4),
                        userId, sessionId, (int) statement.getLong(3)));
            }
        } catch (RuntimeException ignored) {
            // A failed document index is an empty document source, never a network fallback.
        }
        return result;
    }

    DocumentRecord ingest(byte[] content, String displayName, String userId, String sessionId) {
        if (userId == null || userId.trim().isEmpty() || sessionId == null || sessionId.trim().isEmpty()) {
            throw new IllegalArgumentException("user_id and session_id must not be empty");
        }
        String hash = sha256(content);
        String text;
        text = extract(content, displayName);
        if (text.trim().isEmpty()) {
            throw new IllegalArgumentException("document contains no extractable text");
        }
        String documentId = "document-" + sha256((userId + ":" + sessionId + ":" + hash)
                .getBytes(StandardCharsets.UTF_8)).substring(0, 24);
        List<String> chunks = split(text);
        runtime.beginTransaction();
        try {
            deleteDocumentInternal(documentId);
            runtime.execSQL("INSERT INTO documents(document_id,user_id,session_id,display_name,content_hash,created_at,character_count) VALUES(?,?,?,?,?,?,?)",
                    new Object[]{documentId, userId, sessionId, displayName, hash, Instant.now().toString(), text.length()});
            for (int index = 0; index < chunks.size(); index++) {
                String passageId = documentId + "-chunk-" + String.format(Locale.ROOT, "%06d", index);
                runtime.execSQL("INSERT INTO document_passages(passage_id,document_id,user_id,session_id,chunk_index,text) VALUES(?,?,?,?,?,?)",
                        new Object[]{passageId, documentId, userId, sessionId, index, chunks.get(index)});
            }
            runtime.setTransactionSuccessful();
        } finally {
            runtime.endTransaction();
        }
        rebuildDocumentSearchIndex();
        return new DocumentRecord(documentId, userId, sessionId, displayName, hash, text.length());
    }

    void deleteDocument(String documentId, String userId, String sessionId) {
        runtime.beginTransaction();
        try {
            Cursor cursor = runtime.rawQuery("SELECT document_id FROM documents WHERE document_id=? AND user_id=? AND session_id=?",
                    new String[]{documentId, userId, sessionId});
            boolean allowed = cursor.moveToFirst();
            cursor.close();
            if (!allowed) throw new IllegalArgumentException("document is outside the current scope");
            deleteDocumentInternal(documentId);
            runtime.setTransactionSuccessful();
        } finally {
            runtime.endTransaction();
        }
        rebuildDocumentSearchIndex();
    }

    private void deleteDocumentInternal(String documentId) {
        runtime.execSQL("DELETE FROM document_passages WHERE document_id=?", new Object[]{documentId});
        runtime.execSQL("DELETE FROM documents WHERE document_id=?", new Object[]{documentId});
    }

    private void rebuildDocumentSearchIndex() {
        if (!documentFtsAvailable) return;
        try (SQLiteStatement statement = runtimeSearch.prepare(
                "INSERT INTO document_search(document_search) VALUES('rebuild')")) {
            statement.step();
        } catch (RuntimeException exception) {
            documentFtsAvailable = false;
        }
    }

    String formatContext(List<RetrievedPassage> passages, RuntimePolicy.TokenCounter counter) {
        List<RetrievedPassage> bounded = fitPassages(passages, counter);
        StringBuilder result = new StringBuilder();
        for (RetrievedPassage passage : bounded) {
            String block = passage.text;
            if (result.length() > 0) result.append("\n\n");
            result.append(block);
        }
        return result.toString();
    }

    List<RetrievedPassage> fitPassages(
            List<RetrievedPassage> passages, RuntimePolicy.TokenCounter counter) {
        List<RetrievedPassage> selected = new ArrayList<>();
        int used = 0;
        int maximum = Math.min(passages.size(), RuntimePolicy.MAX_RETRIEVED_PASSAGES);
        for (int index = 0; index < maximum; index++) {
            RetrievedPassage passage = passages.get(index);
            int remaining = RuntimePolicy.MAX_RETRIEVED_CONTEXT_TOKENS - used;
            if (remaining <= 0) break;
            int passageTokens = RuntimePolicy.count(passage.text, counter);
            if (passageTokens <= remaining) {
                selected.add(passage);
                used += passageTokens;
                continue;
            }
            String truncated = RuntimePolicy.truncate(passage.text, remaining, counter);
            if (!truncated.isEmpty()) {
                selected.add(new RetrievedPassage(
                        passage.sourceType, passage.passageId, truncated, passage.score,
                        passage.question, passage.lifeStage, passage.topic, passage.timing,
                        passage.population, passage.countryScope, passage.warningSigns,
                        passage.actionBoundary, passage.safetyLevel,
                        passage.documentId, passage.displayName, passage.userId,
                        passage.sessionId, passage.chunkIndex));
            }
            break;
        }
        return selected;
    }

    SQLiteDatabase database() { return runtime; }

    @Override public void close() {
        knowledge.close();
        runtimeSearch.close();
        runtime.close();
    }

    private static List<String> terms(String text) {
        List<String> result = new ArrayList<>();
        for (String token : text.toLowerCase(Locale.ROOT).split("[^\\p{L}\\p{Nd}]+")) {
            if (token.length() < 3 || STOPWORDS.contains(token) || token.matches("\\d+")) continue;
            String normalized = switch (token) {
                case "pregnant", "pregnancies" -> "pregnancy";
                case "heavily" -> "heavy";
                case "bleeding", "bleeds" -> "bleed";
                case "months" -> "month";
                case "weeks" -> "week";
                case "symptoms" -> "symptom";
                case "changes" -> "change";
                case "tests" -> "test";
                case "contraceptive", "contraceptives" -> "contraception";
                case "labour" -> "labor";
                default -> token;
            };
            if (!result.contains(normalized)) result.add(normalized);
        }
        String lowered = text.toLowerCase(Locale.ROOT);
        if ((lowered.contains("family planning") || lowered.contains("birth control"))
                && !result.contains("contraception")) {
            result.add("contraception");
        }
        if (result.contains("contraception")) {
            for (String alias : Arrays.asList(
                    "family", "planning", "birth", "control")) {
                if (!result.contains(alias)) result.add(alias);
            }
        }
        boolean labourContext = (result.contains("labor") || result.contains("labour"))
                && (result.contains("prepare") || result.contains("preparation")
                || result.contains("prepared") || result.contains("planning")
                || result.contains("plan"));
        if (labourContext) {
            if (!result.contains("birth_preparation")) result.add("birth_preparation");
            for (String alias : Arrays.asList(
                    "birth", "preparation", "preparedness", "delivery", "plan")) {
                if (!result.contains(alias)) result.add(alias);
            }
        }
        return result;
    }

    private static String buildMatchQuery(String text) {
        List<String> terms = new ArrayList<>();
        for (String raw : rawTerms(text)) {
            if (!terms.contains(raw)) terms.add(raw);
        }
        for (String normalized : terms(text)) {
            if (!terms.contains(normalized)) terms.add(normalized);
        }
        if (terms.contains("contraception")
                || text.toLowerCase(Locale.ROOT).contains("family planning")
                || text.toLowerCase(Locale.ROOT).contains("birth control")) {
            for (String alias : Arrays.asList(
                    "contraception", "contraceptive", "contraceptives", "family", "planning")) {
                if (!terms.contains(alias)) terms.add(alias);
            }
        }
        if (terms.contains("birth_preparation")) {
            for (String alias : Arrays.asList(
                    "birth", "preparation", "preparedness", "delivery", "plan")) {
                if (!terms.contains(alias)) terms.add(alias);
            }
        }
        StringBuilder result = new StringBuilder();
        for (String term : terms) {
            if (result.length() > 0) result.append(" OR ");
            result.append('"').append(term.replace("\"", "\"\"")) .append('"');
        }
        return result.toString();
    }

    private static List<String> rawTerms(String text) {
        List<String> result = new ArrayList<>();
        for (String token : text.toLowerCase(Locale.ROOT).split("[^\\p{L}\\p{Nd}]+")) {
            if (token.length() < 3 || STOPWORDS.contains(token) || token.matches("\\d+")) continue;
            if (!result.contains(token)) result.add(token);
        }
        return result;
    }

    private static double relevance(List<String> terms, String text) {
        Set<String> available = new HashSet<>(terms(text));
        int matched = 0;
        for (String term : terms) if (available.contains(term)) matched++;
        return terms.isEmpty() ? 0.0 : ((double) matched / terms.size());
    }

    private static int phraseHits(List<String> queryTerms, List<String> textTerms) {
        if (queryTerms.size() < 2 || textTerms.size() < 2) return 0;
        Set<String> textPairs = new HashSet<>();
        for (int index = 0; index + 1 < textTerms.size(); index++) {
            textPairs.add(textTerms.get(index) + "\u0000" + textTerms.get(index + 1));
        }
        int hits = 0;
        for (int index = 0; index + 1 < queryTerms.size(); index++) {
            String pair = queryTerms.get(index) + "\u0000" + queryTerms.get(index + 1);
            if (textPairs.contains(pair)) hits++;
        }
        return hits;
    }

    private static List<String> split(String text) {
        List<String> chunks = new ArrayList<>();
        List<String> paragraphs = new ArrayList<>();
        for (String line : text.split("\\R")) {
            String paragraph = line.trim();
            if (!paragraph.isEmpty()) paragraphs.add(paragraph);
        }
        String current = "";
        for (String paragraph : paragraphs) {
            if (paragraph.length() > 1200) {
                if (!current.isEmpty()) { chunks.add(current); current = ""; }
                int start = 0;
                while (start < paragraph.length()) {
                    int end = Math.min(start + 1200, paragraph.length());
                    chunks.add(paragraph.substring(start, end).trim());
                    if (end == paragraph.length()) break;
                    start = end - 200;
                }
                continue;
            }
            String candidate = current.isEmpty() ? paragraph : current + "\n\n" + paragraph;
            if (candidate.length() <= 1200) current = candidate;
            else {
                chunks.add(current);
                String trailing = current.substring(Math.max(0, current.length() - 200)).trim();
                current = trailing.isEmpty() ? paragraph : trailing + "\n\n" + paragraph;
            }
        }
        if (!current.isEmpty()) chunks.add(current);
        return chunks;
    }

    private String extract(byte[] content, String displayName) {
        String lower = displayName.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".txt") || lower.endsWith(".md") || lower.endsWith(".markdown")) {
            return new String(content, StandardCharsets.UTF_8).replaceFirst("^\\uFEFF", "").trim();
        }
        if (lower.endsWith(".docx")) return extractDocx(content);
        if (lower.endsWith(".pdf")) return extractPdf(content);
        throw new IllegalArgumentException("unsupported document format");
    }

    private String extractPdf(byte[] content) {
        try {
            Class<?> loader = Class.forName("com.tom_roush.pdfbox.android.PDFBoxResourceLoader");
            loader.getMethod("init", Context.class).invoke(null, context);
            Class<?> documentType = Class.forName("org.apache.pdfbox.pdmodel.PDDocument");
            Object document = documentType.getMethod("load", byte[].class).invoke(null, content);
            try {
                Class<?> stripperType = Class.forName("org.apache.pdfbox.text.PDFTextStripper");
                Object stripper = stripperType.getConstructor().newInstance();
                return (String) stripperType.getMethod("getText", documentType).invoke(stripper, document);
            } finally {
                documentType.getMethod("close").invoke(document);
            }
        } catch (Exception exception) {
            throw new IllegalArgumentException("unable to extract PDF text", exception);
        }
    }

    private static String extractDocx(byte[] content) {
        try (ZipInputStream input = new ZipInputStream(new ByteArrayInputStream(content))) {
            ZipEntry entry;
            while ((entry = input.getNextEntry()) != null) {
                if (!"word/document.xml".equals(entry.getName())) continue;
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                input.transferTo(bytes);
                var document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
                        .parse(new InputSource(new StringReader(bytes.toString(StandardCharsets.UTF_8))));
                NodeList bodies = document.getElementsByTagName("w:body");
                StringBuilder text = new StringBuilder();
                if (bodies.getLength() > 0) {
                    NodeList blocks = bodies.item(0).getChildNodes();
                    for (int index = 0; index < blocks.getLength(); index++) {
                        Node block = blocks.item(index);
                        if (!(block instanceof org.w3c.dom.Element)) continue;
                        if ("w:p".equals(block.getNodeName())) {
                            appendDocxBlock(text, block, "\n\n");
                        } else if ("w:tbl".equals(block.getNodeName())) {
                            NodeList rows = ((org.w3c.dom.Element) block).getElementsByTagName("w:tr");
                            for (int rowIndex = 0; rowIndex < rows.getLength(); rowIndex++) {
                                NodeList cells = ((org.w3c.dom.Element) rows.item(rowIndex))
                                        .getElementsByTagName("w:tc");
                                StringBuilder row = new StringBuilder();
                                for (int cellIndex = 0; cellIndex < cells.getLength(); cellIndex++) {
                                    String cell = docxText(cells.item(cellIndex)).trim();
                                    if (!cell.isEmpty()) {
                                        if (row.length() > 0) row.append(" | ");
                                        row.append(cell);
                                    }
                                }
                                if (row.length() > 0) appendTextBlock(text, row.toString(), "\n\n");
                            }
                        }
                    }
                }
                return text.toString().trim();
            }
            return "";
        } catch (Exception exception) {
            throw new IllegalArgumentException("unable to extract DOCX text", exception);
        }
    }

    private static void appendDocxBlock(StringBuilder output, Node block, String separator) {
        String value = docxText(block).trim();
        if (!value.isEmpty()) appendTextBlock(output, value, separator);
    }

    private static String docxText(Node node) {
        NodeList textNodes = ((org.w3c.dom.Element) node).getElementsByTagName("w:t");
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < textNodes.getLength(); index++) {
            result.append(textNodes.item(index).getTextContent());
        }
        return result.toString();
    }

    private static void appendTextBlock(StringBuilder output, String value, String separator) {
        if (output.length() > 0) output.append(separator);
        output.append(value);
    }

    private static String sha256(byte[] value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value);
            StringBuilder result = new StringBuilder();
            for (byte item : digest) result.append(String.format(Locale.ROOT, "%02x", item));
            return result.toString();
        } catch (Exception exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }

    private static final class SearchHit {
        final String passageId;
        final String question;
        final String answer;
        final double matchScore;
        final String lifeStage;
        final String topic;
        final String timing;
        final String population;
        final String countryScope;
        final String warningSigns;
        final String actionBoundary;
        final String safetyLevel;

        SearchHit(String passageId, String question, String answer, double matchScore) {
            this(passageId, question, answer, matchScore, null, null, null, null, null, null, null, null);
        }

        SearchHit(String passageId, String question, String answer, double matchScore,
                  String lifeStage, String topic, String timing, String population,
                  String countryScope, String warningSigns, String actionBoundary, String safetyLevel) {
            this.passageId = passageId;
            this.question = question;
            this.answer = answer;
            this.matchScore = matchScore;
            this.lifeStage = lifeStage;
            this.topic = topic;
            this.timing = timing;
            this.population = population;
            this.countryScope = countryScope;
            this.warningSigns = warningSigns;
            this.actionBoundary = actionBoundary;
            this.safetyLevel = safetyLevel;
        }
    }

    private static final class Candidate {
        final double coverage;
        final int questionPhrases;
        final int answerPhrases;
        final List<String> passageTerms;
        final String passageId;
        final String answer;
        final double ftsRank;
        final String question;
        final String lifeStage;
        final String topic;
        final String timing;
        final String population;
        final String countryScope;
        final String warningSigns;
        final String actionBoundary;
        final String safetyLevel;

        Candidate(double coverage, int questionPhrases, int answerPhrases,
                  List<String> passageTerms, String passageId, String answer,
                  double ftsRank, String question, String lifeStage, String topic,
                  String timing, String population, String countryScope, String warningSigns, String actionBoundary,
                  String safetyLevel) {
            this.coverage = coverage;
            this.questionPhrases = questionPhrases;
            this.answerPhrases = answerPhrases;
            this.passageTerms = passageTerms;
            this.passageId = passageId;
            this.answer = answer;
            this.ftsRank = ftsRank;
            this.question = question;
            this.lifeStage = lifeStage;
            this.topic = topic;
            this.timing = timing;
            this.population = population;
            this.countryScope = countryScope;
            this.warningSigns = warningSigns;
            this.actionBoundary = actionBoundary;
            this.safetyLevel = safetyLevel;
        }
    }

    static final class RetrievedPassage {
        final String sourceType;
        final String passageId;
        final String text;
        final double score;
        final String documentId;
        final String displayName;
        final String userId;
        final String sessionId;
        final Integer chunkIndex;
        final String question;
        final String lifeStage;
        final String topic;
        final String timing;
        final String population;
        final String countryScope;
        final String warningSigns;
        final String actionBoundary;
        final String safetyLevel;

        RetrievedPassage(String sourceType, String passageId, String text, double score,
                         String documentId, String displayName, String userId,
                         String sessionId, Integer chunkIndex) {
            this(sourceType, passageId, text, score, null, null, null, null, null,
                    null, null, null, null, documentId, displayName, userId, sessionId, chunkIndex);
        }

        RetrievedPassage(String sourceType, String passageId, String text, double score,
                         String question, String lifeStage, String topic, String timing,
                         String population, String countryScope, String warningSigns,
                         String actionBoundary, String safetyLevel,
                         String documentId, String displayName, String userId,
                         String sessionId, Integer chunkIndex) {
            this.sourceType = sourceType;
            this.passageId = passageId;
            this.text = text;
            this.score = score;
            this.documentId = documentId;
            this.displayName = displayName;
            this.userId = userId;
            this.sessionId = sessionId;
            this.chunkIndex = chunkIndex;
            this.question = question;
            this.lifeStage = lifeStage;
            this.topic = topic;
            this.timing = timing;
            this.population = population;
            this.countryScope = countryScope;
            this.warningSigns = warningSigns;
            this.actionBoundary = actionBoundary;
            this.safetyLevel = safetyLevel;
        }

        JsonObject toJson() {
            JsonObject result = new JsonObject();
            result.addProperty("source_type", sourceType);
            result.addProperty("passage_id", passageId);
            result.addProperty("text", text);
            result.addProperty("score", score);
            if (documentId != null) result.addProperty("document_id", documentId);
            if (displayName != null) result.addProperty("display_name", displayName);
            if (userId != null) result.addProperty("user_id", userId);
            if (sessionId != null) result.addProperty("session_id", sessionId);
            if (chunkIndex != null) result.addProperty("chunk_index", chunkIndex);
            return result;
        }
    }

    static final class DocumentRecord {
        final String documentId;
        final String userId;
        final String sessionId;
        final String displayName;
        final String contentHash;
        final int characterCount;

        DocumentRecord(String documentId, String userId, String sessionId,
                       String displayName, String contentHash, int characterCount) {
            this.documentId = documentId;
            this.userId = userId;
            this.sessionId = sessionId;
            this.displayName = displayName;
            this.contentHash = contentHash;
            this.characterCount = characterCount;
        }

        JsonObject toJson() {
            JsonObject result = new JsonObject();
            result.addProperty("document_id", documentId);
            result.addProperty("user_id", userId);
            result.addProperty("session_id", sessionId);
            result.addProperty("display_name", displayName);
            result.addProperty("content_hash", contentHash);
            result.addProperty("character_count", characterCount);
            return result;
        }
    }
}
