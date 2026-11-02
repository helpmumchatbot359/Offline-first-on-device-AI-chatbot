package com.example.mama_ai;

import android.content.res.AssetManager;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Reads a small text file from the Android assets folder.
 *
 * WHY THIS EXISTS: the model package puts its files in sub-folders
 * (contracts/tool_contract.json, prompts/system_prompt.txt) but the old code
 * only looked in the assets ROOT, so the file was "not found". This helper
 * tries every place the file may live, and when all of them fail it says
 * exactly which paths were tried and what the assets root really contains.
 */
final class AssetText {
    private AssetText() {}

    /** Tries each path in order and returns the text of the first one that opens. */
    static String read(AssetManager assets, String... candidatePaths) throws IOException {
        StringBuilder tried = new StringBuilder();
        IOException last = null;
        for (String path : candidatePaths) {
            try (InputStream stream = assets.open(path);
                 InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                StringBuilder text = new StringBuilder();
                char[] buffer = new char[4096];
                int count;
                while ((count = reader.read(buffer)) >= 0) text.append(buffer, 0, count);
                // A byte-order mark (invisible first character) breaks some JSON parsers.
                if (text.length() > 0 && text.charAt(0) == '\uFEFF') text.deleteCharAt(0);
                return text.toString();
            } catch (IOException exception) {
                last = exception;
                if (tried.length() > 0) tried.append(", ");
                tried.append(path);
            }
        }
        throw new FileNotFoundException(
                "asset not found. Tried: [" + tried + "]. Assets root contains: " + listRoot(assets)
                        + (last == null || last.getMessage() == null ? "" : " (last error: " + last.getMessage() + ")"));
    }

    private static String listRoot(AssetManager assets) {
        try {
            String[] names = assets.list("");
            return names == null ? "[]" : Arrays.toString(names);
        } catch (IOException exception) {
            return "[unreadable]";
        }
    }
}
