package com.helpmum.mamaBot;

import com.google.ai.edge.litertlm.ThinkingConfig;

/** Model-specific LiteRT-LM behavior used by the product runtime. */
interface RuntimeModelProfile {
    String name();

    ThinkingConfig textThinkingConfig();

    ThinkingConfig toolThinkingConfig();

    boolean automaticToolCalling();

    boolean multimodalInputs();
}
