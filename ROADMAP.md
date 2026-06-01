# Roadmap

## Shipped

**Dictation mode (v2.0.0)**
Hold-to-speak dictation with configurable hotkeys, floating overlay, and text injection at cursor. Uses GrembleVoice streaming ASR.

**Multilingual transcription (v1.1.0)**
Upgraded from Parakeet-TDT v2 (English-only) to v3 (25 European languages). Auto-detects spoken language.

**Signed + notarized builds (v2.0.0)**
GitHub Actions CI pipeline produces signed and notarized DMGs. No more Gatekeeper warnings.

**Vocabulary correction (v2.0.0)**
3-pass post-ASR correction: explicit error mapping, case normalization, fuzzy matching for near-misses. Ships with a bundled Canadian Politics pack; custom vocabulary files supported via Settings.

**On-device transcript refinement (v2.0.0)**
Optional post-session cleanup via Llama 3.2 3B (MLX). Fixes proper nouns and grammar with validation guards against hallucination. All processing on-device.

## Up next

**Background post-processing**
Finalize transcripts in the background after a session stops so a new recording can start immediately. Improves the back-to-back meetings flow.

**Additional vocabulary packs**
Bundled term + correction packs for other domains (legal, medical, technology). Builds on the Canadian Politics pack pattern.

**JSONL crash recovery**
Rebuild transcripts from session data if the app exits mid-session.
