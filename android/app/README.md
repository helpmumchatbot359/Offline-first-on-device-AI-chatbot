# MamaAI Gemma LiteRT-LM Android Handoff

Package: `mamaai-gemma-4-e2b-2026.10.22`

This release contains the unchanged Gemma `.litertlm` model, the read-only local knowledge index, the shared tool contract and the system prompt. The mobile app owns mutable chat, telemetry, feedback and synchronization state; none of those databases are included.

Use `package_manifest.json` to verify component hashes before copying the model into app-private storage. Keep the `.litertlm` extension.
