# Privacy

Detto processes everything on your Mac. No audio, text, or metadata ever leaves the device.

## Data Flow

| Stage | What happens | Where it goes |
|---|---|---|
| Audio capture | Mic and/or system audio captured in memory | RAM only, never written to disk |
| Transcription | Parakeet-TDT v3 runs inference on-device | CPU/GPU/ANE on your Mac |
| Output | Text transcript saved as `.md` | A folder you choose |

## What Detto stores

- **Text transcripts** as plain `.md` files in your chosen output folder.
- **ASR model cache** (~600MB for Parakeet, ~2GB for Llama 3.2 3B). Downloaded on first launch, cached locally after that.
- **User preferences** (hotkey, output path, mic selection) via macOS UserDefaults. Also stores security-scoped folder bookmarks so vault access persists across reboots.
- **Session metadata** as JSONL files in `~/Library/Application Support/Detto/sessions/`. Contains timestamps, duration, and speaker counts per session. No transcript content.
- **Application logs** in `~/Library/Logs/Detto/`. Contain operational events (start, stop, errors, timing). No transcript content. Rotated automatically, keeping the 5 most recent files.

## What Detto does NOT store

- Raw audio. No recordings are saved to disk, ever.
- Analytics, telemetry, or usage data.
- Account information. There are no accounts.

## Network activity

Detto makes two types of network calls:

- **Model downloads.** On first launch, Detto downloads the Parakeet ASR model (~600MB) and the Llama 3.2 3B refinement model (~2GB) from Hugging Face. These are cached locally and not downloaded again.
- **Sparkle update checks.** Periodically fetches `appcast.xml` from GitHub Pages to check for new versions. This can be disabled in Settings. No user data is included in the request.

There are no other network calls. No analytics SDKs. No crash reporting. No telemetry. No third-party frameworks that phone home.

## Third-party dependencies

- [GrembleVoice](https://github.com/Gremble-io/gremble-voice) (local ASR engine, no network activity)
- [Sparkle](https://sparkle-project.org) (update checks only, open source)

Both are open source. Neither collects or transmits user data.
