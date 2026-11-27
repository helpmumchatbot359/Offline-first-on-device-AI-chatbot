package com.helpmum.mamaBot;

import com.google.ai.edge.litertlm.ThinkingConfig;

/** Gemma 4 E2B product-runtime settings. */
final class GemmaRuntimeProfile implements RuntimeModelProfile {
    static final GemmaRuntimeProfile INSTANCE = new GemmaRuntimeProfile();

    private GemmaRuntimeProfile() {
    }

    @Override
    public String name() {
        return "gemma";
    }

    @Override
    public ThinkingConfig textThinkingConfig() {
        return new ThinkingConfig(false);
    }

    @Override
    public ThinkingConfig toolThinkingConfig() {
        return new ThinkingConfig(false);
    }

    @Override
    public boolean automaticToolCalling() {
        // OfflineMamaAiRuntime owns validation, events and the bounded tool loop.
        return false;
    }

    @Override
    public boolean multimodalInputs() {
        return false;
    }
}
