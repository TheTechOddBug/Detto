# Changelog

## [2.0.0] — 2026-06-02
Initial public release of Detto, a complete rewrite of Tome. All processing on-device.

### Added
- **Dictation mode**: hold-to-speak with configurable hotkeys (Control, Fn, Right Option, Right Command, Hyper Key, custom combos). Floating overlay with waveform visualization. Text injection at the cursor.
- **Client briefing system**: vault-aware context loading, attendee tracking, per-client transcript folders. Reads client metadata from your Obsidian vault.
- **Vocabulary correction**: 3-pass post-ASR correction (explicit mappings, case normalization, fuzzy matching). Bundled Canadian Politics pack (53 terms, 30 corrections); custom vocabulary file support via Settings.
- **On-device transcript refinement**: optional post-session cleanup via Llama 3.2 3B (MLX). Fixes proper nouns and grammar with five validation guards against hallucination.
- **Channel-based speaker separation**: dual-stream mic + system audio with per-stream VAD and ASR. Improved diarization on call recordings.
- **Confidence scores**: Parakeet ASR confidence captured per utterance and used to skip refinement on high-confidence segments.

### Changed
- ASR engine: Parakeet-TDT v3 via GrembleVoice (25 European languages, multilingual auto-detection).
- License: MIT → Business Source License 1.1 (converts to MIT 2030-05-12). Existing Tome v1 forks retain their MIT copy.
- CI: signed and notarized DMG builds via GitHub Actions.

### Removed
- Tome v1 codebase (complete rewrite).

## [1.2.2] — 2026-03-31
- Raised VAD threshold on system audio stream to reduce echo bleed during calls

## [1.2.0] — 2026-03-30
- Upgraded FluidAudio to latest (actor-based AsrManager), fixes Swift 6 build failures on Xcode 26.4+
- Build script now fails on missing code signing identity instead of silently shipping unsigned
- Added Gatekeeper troubleshooting to README

## [1.1.0] — 2026-03-29
- Multilingual transcription: Parakeet-TDT v3, 25 European languages with auto-detection
- Pinned FluidAudio to 0.12.1

## [1.0.1] — 2026-03-28
- Spectrum visualizer replaces static waveform (reactive bars, peak hold, dynamic glow)
- Visual redesign: warm glass UI, chat-style transcript bubbles
- Pulsing recording indicator, silence countdown, keyboard shortcuts (⌘R, ⌘⇧R, ⌘.)
- Diarization progress messages during post-session processing
- Error visibility and save confirmation banner
- Session cleanup and async handling fixes

## [1.0.0] — 2026-03-24
- Initial release
- Local transcription via Parakeet-TDT v2 on Apple Silicon
- Call capture (mic + system audio) with per-app filtering
- Voice memo mode
- Speaker diarization
- Vault-native .md output with YAML frontmatter
- Sparkle auto-updates
