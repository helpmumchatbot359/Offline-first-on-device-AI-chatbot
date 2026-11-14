package com.helpmum.mamaBot;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Lexical retrieval with a high-confidence bypass and secondary metadata gates.
 *
 * <p>Passages scoring at or above {@link #HIGH_CONFIDENCE_LEXICAL_SCORE} are
 * admitted directly. Metadata and action gates are applied only to lower-scoring
 * candidates, so a strong lexical match cannot be discarded solely because the
 * deterministic query profile guessed the wrong topic.</p>
 */
final class Retrieval {
    private static final int CANDIDATE_LIMIT = 12;
    private static final double MIN_NORMALIZED_SCORE = 80.0;
    private static final double MIN_RAW_METADATA_SCORE = 65.0;
    private static final double HIGH_CONFIDENCE_LEXICAL_SCORE = 95.0;

    static final class QueryProfile {
        final String topic;
        final String lifeStage;
        final String population;
        final String timing;
        final String countryScope;
        final String requestedAction;

        QueryProfile(String topic, String lifeStage, String population, String timing,
                String countryScope, String requestedAction) {
            this.topic = topic;
            this.lifeStage = lifeStage;
            this.population = population;
            this.timing = timing;
            this.countryScope = countryScope;
            this.requestedAction = requestedAction;
        }

        JsonObject toJson() {
            JsonObject value = new JsonObject();
            value.addProperty("topic", topic);
            value.addProperty("life_stage", lifeStage);
            value.addProperty("population", population);
            value.addProperty("timing", timing);
            value.addProperty("country_scope", countryScope);
            value.addProperty("requested_action", requestedAction);
            return value;
        }
    }

    static QueryProfile profile(String query) {
        String value = query.toLowerCase(java.util.Locale.ROOT)
                .replaceAll("\\s+", " ").trim();
        boolean records = containsProfileTerm(value,
                "record", "records", "document", "documents", "health card",
                "immunization card", "certificate")
                || (value.contains("keep") && value.contains("information"));
        boolean vaccination = containsProfileTerm(value,
                "vaccine", "vaccination", "immuniz", "tetanus", "tdap", "bcg",
                "opv", "pentavalent", "measles");
        boolean newborn = containsProfileTerm(value,
                "newborn", "baby", "infant", "umbilical", "cord stump", "navel", "breastfeed");
        boolean postpartum = containsProfileTerm(value,
                "postpartum", "after delivery", "after birth", "after giving birth", "postnatal",
                "lying-in", "caesarean", "cesarean", "c-section");
        boolean antenatal = containsProfileTerm(value,
                "antenatal", "prenatal", "antenatal visit", "prenatal visit", "clinic visit");
        boolean medication = containsProfileTerm(value,
                "medicine", "medication", "drug", "tablet", "dose", "overdose", "herb", "remedy", "exposure");
        boolean contraception = containsProfileTerm(value,
                "contracept", "family planning", "birth control");
        boolean warningSigns = containsProfileTerm(value,
                "warning sign", "danger sign", "emergency", "urgent", "bleeding", "severe pain", "convulsion", "fainting");
        boolean nutrition = containsProfileTerm(value,
                "nutrition", "nutritious", "diet", "food", "exercise", "physical activity");
        String topic;
        String action;
        if (records) {
            topic = "health_records_and_continuity";
            action = "records";
        } else if (vaccination) {
            topic = "vaccination";
            action = containsProfileTerm(value, "when", "schedule", "dose", "week", "month", "contact")
                    ? "schedule" : "explanation";
        } else if (warningSigns) {
            topic = "warning_signs_and_escalation";
            action = "urgent_escalation";
        } else if (medication) {
            topic = "medication_and_exposure";
            action = containsProfileTerm(value, "what do i do", "what should i do", "help")
                    ? "home_care" : "explanation";
        } else if (contraception) {
            topic = "postpartum_and_newborn";
            action = "contraception";
        } else if (antenatal) {
            topic = "antenatal_care";
            if (containsProfileTerm(value, "first", "initial")) {
                action = "first_visit_orientation";
            } else {
                action = containsProfileTerm(value, "why", "check", "monitor", "measure")
                        ? "monitoring_reason" : "explanation";
            }
        } else if (newborn || postpartum) {
            topic = "postpartum_and_newborn";
            action = containsProfileTerm(value, "how", "care", "do", "help")
                    ? "home_care" : "explanation";
        } else if (nutrition) {
            topic = "nutrition_and_exercise";
            action = "prevention";
        } else {
            topic = "common_maternal_child_concerns";
            action = containsProfileTerm(value, "how", "what can i do", "help")
                    ? "home_care" : "explanation";
        }
        String lifeStage;
        if (contraception && postpartum) lifeStage = "postpartum_or_breastfeeding";
        else if (newborn) lifeStage = "newborn_or_infant";
        else if (postpartum) lifeStage = "postpartum_or_breastfeeding";
        else if (containsProfileTerm(value, "pregnan", "antenatal", "prenatal")) lifeStage = "pregnancy";
        else if (containsProfileTerm(value, "child", "children", "toddler")) lifeStage = "child";
        else lifeStage = "maternal_child_general";
        String country = containsProfileTerm(value, "nigeria", "nigerian", "naija")
                ? "Nigeria" : "African_context_general";
        return new QueryProfile(topic, lifeStage, "African_maternal_child_users",
                vaccination ? "schedule_sensitive" : "not_applicable", country, action);
    }

    private static boolean actionMatches(
            QueryProfile profile, LocalRagStore.RetrievedPassage passage) {
        String value = passage.question == null
                ? "" : passage.question.toLowerCase(java.util.Locale.ROOT);
        if (profile.requestedAction.equals("monitoring_reason")) {
            boolean monitoring = containsProfileTerm(value, "check", "monitor", "measure", "screen", "why");
            boolean management = containsProfileTerm(value, "manage", "prevent", "treat", "control", "deal with");
            return monitoring && !management;
        }
        if (profile.requestedAction.equals("first_visit_orientation")) {
            return containsProfileTerm(value, "first", "initial");
        }
        if (profile.requestedAction.equals("contraception")) {
            return containsProfileTerm(value, "contracept", "family planning", "birth control");
        }
        return true;
    }

    private static boolean containsProfileTerm(String value, String... terms) {
        for (String term : terms) if (value.contains(term)) return true;
        return false;
    }

    private static String normalizeProfileValue(String value) {
        if (value == null) return "";
        String normalized = value.toLowerCase(java.util.Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "_")
                .replaceAll("^_+|_+$", "");
        if (normalized.equals("not_stated")) return "unknown";
        if (normalized.equals("africa_general") || normalized.equals("african_general")) {
            return "african_context_general";
        }
        if (normalized.equals("antenatal") || normalized.equals("prenatal")) return "antenatal_care";
        if (normalized.equals("postpartum") || normalized.equals("postpartum_breastfeeding")) {
            return "postpartum_or_breastfeeding";
        }
        if (normalized.equals("newborn") || normalized.equals("infant")) return "newborn_or_infant";
        if (normalized.equals("child_health")) return "child";
        if (normalized.equals("records") || normalized.equals("health_records")) {
            return "health_records_and_continuity";
        }
        if (normalized.equals("immunization") || normalized.equals("immunisation")) return "vaccination";
        if (normalized.equals("warning_signs")) return "warning_signs_and_escalation";
        return normalized;
    }

    private static boolean isMaternalChildStage(String value) {
        return value.equals("maternal_child_general")
                || value.equals("pregnancy")
                || value.equals("postpartum_or_breastfeeding")
                || value.equals("newborn_or_infant")
                || value.equals("child");
    }

    private static boolean profileMatchesValue(String expected, String actual) {
        String expectedValue = normalizeProfileValue(expected);
        String actualValue = normalizeProfileValue(actual);
        if (expectedValue.isEmpty() || expectedValue.equals("unknown")) return true;
        if (actualValue.isEmpty() || actualValue.equals("unknown")) return true;
        if (expectedValue.equals(actualValue)) return true;
        if (expectedValue.equals("maternal_child_general")) {
            return isMaternalChildStage(actualValue);
        }
        if (actualValue.equals("maternal_child_general")) {
            return isMaternalChildStage(expectedValue);
        }
        if ((expectedValue.equals("child") && actualValue.equals("newborn_or_infant"))
                || (expectedValue.equals("newborn_or_infant") && actualValue.equals("child"))) {
            return true;
        }
        if (expectedValue.equals("african_context_general")) {
            return actualValue.equals("african_context_general")
                    || actualValue.equals("nigeria")
                    || actualValue.equals("ghana")
                    || actualValue.equals("malawi");
        }
        if (actualValue.equals("african_context_general")) {
            return expectedValue.equals("african_context_general")
                    || expectedValue.equals("nigeria")
                    || expectedValue.equals("ghana")
                    || expectedValue.equals("malawi");
        }
        return false;
    }

    private static boolean metadataMatches(
            QueryProfile profile, LocalRagStore.RetrievedPassage passage) {
        return profileMatchesValue(profile.topic, passage.topic)
                && profileMatchesValue(profile.lifeStage, passage.lifeStage)
                && profileMatchesValue(profile.population, passage.population)
                && profileMatchesValue(profile.timing, passage.timing)
                && profileMatchesValue(profile.countryScope, passage.countryScope);
    }

    private static List<LocalRagStore.RetrievedPassage> filterCandidates(
            QueryProfile profile, List<LocalRagStore.RetrievedPassage> passages) {
        List<LocalRagStore.RetrievedPassage> filtered = new ArrayList<>();
        for (LocalRagStore.RetrievedPassage passage : passages) {
            if (passage.score >= MIN_RAW_METADATA_SCORE
                    && passage.score < HIGH_CONFIDENCE_LEXICAL_SCORE
                    && metadataMatches(profile, passage)
                    && actionMatches(profile, passage)) {
                filtered.add(passage);
            }
        }
        return filtered;
    }

    private static List<LocalRagStore.RetrievedPassage> normalizeCandidateScores(
            List<LocalRagStore.RetrievedPassage> passages) {
        if (passages.isEmpty()) return new ArrayList<>();
        double lowest = passages.get(0).score;
        double highest = passages.get(0).score;
        for (LocalRagStore.RetrievedPassage passage : passages) {
            lowest = Math.min(lowest, passage.score);
            highest = Math.max(highest, passage.score);
        }
        double spread = highest - lowest;
        List<LocalRagStore.RetrievedPassage> normalized = new ArrayList<>(passages.size());
        for (LocalRagStore.RetrievedPassage passage : passages) {
            double score = spread == 0.0
                    ? 100.0
                    : ((passage.score - lowest) / spread) * 100.0;
            normalized.add(new LocalRagStore.RetrievedPassage(
                    passage.sourceType, passage.passageId, passage.text, score,
                    passage.question, passage.lifeStage, passage.topic, passage.timing,
                    passage.population, passage.countryScope, passage.warningSigns,
                    passage.actionBoundary, passage.safetyLevel, passage.documentId,
                    passage.displayName, passage.userId, passage.sessionId,
                    passage.chunkIndex));
        }
        return normalized;
    }

    private static void addMetadata(
            JsonObject value, LocalRagStore.RetrievedPassage passage) {
        if (passage.question != null) value.addProperty("question", passage.question);
        if (passage.lifeStage != null) value.addProperty("life_stage", passage.lifeStage);
        if (passage.topic != null) value.addProperty("topic", passage.topic);
        if (passage.timing != null) value.addProperty("timing", passage.timing);
        if (passage.population != null) value.addProperty("population", passage.population);
        if (passage.countryScope != null) value.addProperty("country_scope", passage.countryScope);
        if (passage.warningSigns != null) value.addProperty("warning_signs", passage.warningSigns);
        if (passage.actionBoundary != null) {
            value.addProperty("action_boundary", passage.actionBoundary);
        }
        if (passage.safetyLevel != null) value.addProperty("safety_level", passage.safetyLevel);
    }

    private Retrieval() {}

    static List<LocalRagStore.RetrievedPassage> retrieve(
            LocalRagStore rag, String query, String userId, String sessionId) {
        return retrieveDetailed(rag, query, userId, sessionId).passages;
    }

    static Outcome retrieveDetailed(
            LocalRagStore rag, String query, String userId, String sessionId) {
        QueryProfile queryProfile = profile(query);
        List<LocalRagStore.RetrievedPassage> candidates;
        try {
            candidates = rag.retrieveCandidates(query, userId, sessionId, CANDIDATE_LIMIT);
        } catch (Throwable throwable) {
            return new Outcome(Collections.emptyList(), queryProfile, new JsonArray(),
                    throwable.toString(), 0, 0);
        }
        List<LocalRagStore.RetrievedPassage> rawCandidates = candidates;
        List<LocalRagStore.RetrievedPassage> strong = new ArrayList<>();
        for (LocalRagStore.RetrievedPassage passage : rawCandidates) {
            double threshold = "user_document".equals(passage.sourceType)
                    ? HIGH_CONFIDENCE_LEXICAL_SCORE / 100.0
                    : HIGH_CONFIDENCE_LEXICAL_SCORE;
            if (passage.score >= threshold) strong.add(passage);
        }
        List<LocalRagStore.RetrievedPassage> metadataCandidates =
                filterCandidates(queryProfile, rawCandidates);
        List<LocalRagStore.RetrievedPassage> pool = new ArrayList<>();
        for (LocalRagStore.RetrievedPassage passage : strong) {
            if (pool.size() >= RuntimePolicy.MAX_RETRIEVED_PASSAGES) break;
            pool.add(passage);
        }
        for (LocalRagStore.RetrievedPassage passage : metadataCandidates) {
            if (pool.size() >= RuntimePolicy.MAX_RETRIEVED_PASSAGES) break;
            if (!containsPassage(pool, passage.passageId)) pool.add(passage);
        }
        candidates = normalizeCandidateScores(pool);
        List<LocalRagStore.RetrievedPassage> eligible = filterNormalizedCandidates(candidates);
        eligible.sort(Comparator.comparingDouble(
                (LocalRagStore.RetrievedPassage value) -> value.score).reversed());
        List<LocalRagStore.RetrievedPassage> bounded =
                eligible.size() > RuntimePolicy.MAX_RETRIEVED_PASSAGES
                        ? new ArrayList<>(eligible.subList(0, RuntimePolicy.MAX_RETRIEVED_PASSAGES))
                        : eligible;
        return new Outcome(bounded, queryProfile, candidateValues(candidates, eligible), "",
                candidates.size(), eligible.size());
    }

    private static List<LocalRagStore.RetrievedPassage> filterNormalizedCandidates(
            List<LocalRagStore.RetrievedPassage> passages) {
        List<LocalRagStore.RetrievedPassage> filtered = new ArrayList<>();
        for (LocalRagStore.RetrievedPassage passage : passages) {
            if (passage.score >= MIN_NORMALIZED_SCORE) filtered.add(passage);
        }
        return filtered;
    }

    static JsonArray candidateValues(
            List<LocalRagStore.RetrievedPassage> candidates,
            List<LocalRagStore.RetrievedPassage> eligible) {
        JsonArray result = new JsonArray();
        for (LocalRagStore.RetrievedPassage passage : candidates) {
            JsonObject value = new JsonObject();
            value.addProperty("passage_id", passage.passageId);
            value.addProperty("lexical_score", passage.score);
            addMetadata(value, passage);
            value.addProperty("eligible", containsPassage(eligible, passage.passageId));
            result.add(value);
        }
        return result;
    }

    private static boolean containsPassage(
            List<LocalRagStore.RetrievedPassage> passages, String passageId) {
        for (LocalRagStore.RetrievedPassage passage : passages) {
            if (passage.passageId.equals(passageId)) return true;
        }
        return false;
    }

    static final class Outcome {
        final List<LocalRagStore.RetrievedPassage> passages;
        final QueryProfile profile;
        final JsonArray candidates;
        final String error;
        final int candidateCount;
        final int eligibleCount;

        Outcome(List<LocalRagStore.RetrievedPassage> passages, QueryProfile profile,
                JsonArray candidates, String error, int candidateCount, int eligibleCount) {
            this.passages = passages;
            this.profile = profile;
            this.candidates = candidates;
            this.error = error;
            this.candidateCount = candidateCount;
            this.eligibleCount = eligibleCount;
        }
    }
}
