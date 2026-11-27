package com.helpmum.mamaBot;

import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** Model registry shared by the product bridge and product runtime. */
final class RuntimeModelProfiles {
    private static final Map<String, RuntimeModelProfile> MODELS = modelRegistry();

    private RuntimeModelProfiles() {
    }

    static RuntimeModelProfile defaultProfile() {
        return MODELS.get("gemma");
    }

    /**
     * Select an explicit profile, or infer one from the supplied artifact name.
     * The path remains owned by the application and is never hardcoded here.
     */
    static RuntimeModelProfile select(String requested, String modelPath) {
        String value = requested;
        if (value == null || value.trim().isEmpty()) {
            String path = modelPath == null ? "" : modelPath.toLowerCase(Locale.ROOT);
            value = path.contains("qwen") ? "qwen_rtlm" : "gemma";
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT)
                .replace('-', '_')
                .replace(' ', '_');
        if ("qwen".equals(normalized) || "qwen3_5".equals(normalized)) {
            normalized = "qwen_rtlm";
        } else if ("gemma4".equals(normalized) || "gemma_4_e2b".equals(normalized)) {
            normalized = "gemma";
        }
        RuntimeModelProfile profile = MODELS.get(normalized);
        if (profile == null) {
            throw new IllegalArgumentException(
                    "Unknown model profile '" + value + "'. Use gemma or qwen_rtlm.");
        }
        return profile;
    }

    private static Map<String, RuntimeModelProfile> modelRegistry() {
        Map<String, RuntimeModelProfile> models = new HashMap<>();
        models.put("gemma", GemmaRuntimeProfile.INSTANCE);
        models.put("qwen_rtlm", QwenRtlmRuntimeProfile.INSTANCE);
        return Collections.unmodifiableMap(models);
    }
}
