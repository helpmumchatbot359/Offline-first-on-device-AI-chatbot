package com.example.mama_ai;

import android.app.Activity;
import android.content.Context;

import com.google.ai.edge.litertlm.Backend;
import com.google.ai.edge.litertlm.ActivationDataType;
import com.google.ai.edge.litertlm.EngineConfig;

import java.io.File;
import java.util.Locale;

/** Shared configuration for the Android inference runtime. */
final class RuntimeTuning {
    static final int DEFAULT_MAX_CONTEXT_TOKENS = 4096;

    private RuntimeTuning() {
    }

    static EngineConfig createEngineConfig(Activity activity, String modelPath) {
        Backend backend = backend(activity);
        int maxContextTokens = maxContextTokens(activity);
        return createEngineConfig(activity, modelPath, backend, maxContextTokens);
    }

    static EngineConfig createEngineConfig(Context context, String modelPath) {
        return createEngineConfig(context, modelPath, "cpu", DEFAULT_MAX_CONTEXT_TOKENS);
    }

    static EngineConfig createEngineConfig(
            Context context, String modelPath, String requestedBackend, int maxContextTokens) {
        return createEngineConfig(
                context, modelPath, backend(context, requestedBackend),
                maxContextTokens > 0 ? maxContextTokens : DEFAULT_MAX_CONTEXT_TOKENS);
    }

    private static EngineConfig createEngineConfig(
            Context context,
            String modelPath,
            Backend backend,
            int maxContextTokens) {
        File cacheDirectory = new File(context.getCacheDir(), "litertlm-engine-cache");
        if (!cacheDirectory.exists() && !cacheDirectory.mkdirs()) {
            throw new IllegalStateException(
                    "Unable to create LiteRT-LM cache directory: " + cacheDirectory);
        }

        return new EngineConfig(
                modelPath,
                backend,
                null,
                null,
                maxContextTokens,
                null,
                cacheDirectory.getAbsolutePath(),
                backend instanceof Backend.GPU ? ActivationDataType.FLOAT16 : null);
    }

    static String backendName(Activity activity) {
        return backend(activity).getName();
    }

    static int maxContextTokens(Activity activity) {
        int configured = activity.getIntent().getIntExtra(
                "max_context_tokens", DEFAULT_MAX_CONTEXT_TOKENS);
        return configured > 0 ? configured : DEFAULT_MAX_CONTEXT_TOKENS;
    }

    static boolean prefillPreface(Activity activity) {
        return activity.getIntent().getBooleanExtra("prefill_preface", false);
    }

    static String cachePath(Activity activity) {
        return new File(activity.getCacheDir(), "litertlm-engine-cache")
                .getAbsolutePath();
    }

    private static Backend backend(Activity activity) {
        String requested = activity.getIntent().getStringExtra("backend");
        if (requested == null) {
            requested = "cpu";
        }
        return backend(activity, requested);
    }

    private static Backend backend(Context context, String requested) {
        switch (requested.toLowerCase(Locale.ROOT)) {
            case "gpu":
                return new Backend.GPU();
            case "npu":
                return new Backend.NPU(context.getApplicationInfo().nativeLibraryDir);
            case "cpu":
                return new Backend.CPU();
            default:
                throw new IllegalArgumentException("Unsupported Android backend: " + requested);
        }
    }
}
