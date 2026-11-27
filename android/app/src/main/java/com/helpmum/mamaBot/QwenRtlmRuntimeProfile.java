package com.helpmum.mamaBot;

import com.google.ai.edge.litertlm.ThinkingConfig;

/** Qwen3.5 0.8B LiteRT-LM product-runtime settings. */
final class QwenRtlmRuntimeProfile implements RuntimeModelProfile {
    static final QwenRtlmRuntimeProfile INSTANCE = new QwenRtlmRuntimeProfile();

    private QwenRtlmRuntimeProfile() {
    }

    @Override
    public String name() {
        return "qwen_rtlm";
    }

    @Override
    public ThinkingConfig textThinkingConfig() {
        return new ThinkingConfig(false);
    }

    @Override
    public ThinkingConfig toolThinkingConfig() {
        return new ThinkingConfig(true, 256);
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
