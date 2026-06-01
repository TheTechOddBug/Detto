# Detto Architecture

## System overview

```
+-----------------------------------------------------------+
|  Detto.app                                                |
|                                                           |
|  +----------+  +------------------+  +---------------+    |
|  |  Views   |  |  Dictation       |  |  Settings     |    |
|  |  (SwiftUI)|  |  Controller     |  |  (AppSettings)|    |
|  +----+-----+  +-------+----------+  +---------------+    |
|       |                |                                   |
|  +----v----------------v-------------------------------+  |
|  |              ContentView (orchestrator)              |  |
|  +--+--------------+---------------------+-------------+  |
|     |              |                     |                 |
|  +--v-------+  +---v------+  +-----------v---------+      |
|  |Transcript|  | Session  |  | Transcript          |      |
|  |Engine    |  | Store    |  | Logger              |      |
|  |(realtime)|  | (JSONL)  |  | (markdown)          |      |
|  +--+-+-+---+  +----------+  +---------------------+      |
|     | | |                                                  |
|  +--v-+ +v-----------+                                     |
|  |Mic |  |SystemAudio |                                    |
|  |Cap |  |Capture     |                                    |
|  +----+  +------------+                                    |
+-------------------+---------------------------------------+
                    | imports
       +------------v---------------------------+
       |  gremble-voice                         |
       |                                        |
       |  GrembleVoiceCore (protocols/types)    |
       |  GrembleVoiceParakeet (ASR + diar)     |
       |  GrembleVoiceEngine (pipeline)         |
       |  GrembleVoiceWhisper (alt ASR)         |
       |  GrembleVoiceRefinement (LLM)          |
       |  GrembleVoiceCloud (cloud APIs)        |
       |  GrembleVoiceAudio (mic/file)          |
       +----------------------------------------+
```

## Two independent transcription paths

### 1. Meeting transcription (TranscriptionEngine, dual stream)

```
Mic audio --> MicCapture --> Resample 16kHz --> VADProcessor --> ParakeetStreamingEngine.transcribe()
                                                                        |
                                                                   Utterance("You")
                                                                        |
System audio --> SystemAudioCapture --> Resample 16kHz --+-> VAD (inline) --> ParakeetStreamingEngine.transcribe()
                                                        |                           |
                                                        +-> StreamingDiarizationEngine.addAudio()
                                                                   |                |
                                                                   +-> attributeSpeaker(midpoint)
                                                                             |
                                                                   Utterance("Them" / speaker name)
                                                                             |
                                                                        TranscriptStore --> TranscriptView
                                                                             |
                                                                   TranscriptLogger (markdown file)
                                                                   SessionStore (JSONL)
```

### 2. Dictation (DictationController, single stream)

```
Hotkey press --> HotkeyManager --> DictationController.startRecording()
                                         |
                                  GrembleVoicePipeline.startRecording()
                                         |
                                  Mic --> ASR --> Dictionary --> Refinement
                                         |
Hotkey release --> stopRecording() --> GrembleSession (text at each stage)
                                         |
                                  TextInjector.inject(text)
                                         |
                                  Clipboard --> Cmd+V --> Restore clipboard
```

## File map by layer

### App (5 files)

| File | Purpose |
|------|---------|
| `App/DettoApp.swift` | @main entry, window/menubar/settings scenes |
| `App/AppUpdaterController.swift` | Sparkle auto-update integration |
| `App/FileLogger.swift` | Release-mode file logger (`~/Library/Logs/Detto/`), rotation |
| `App/MenuBarIcon.swift` | Animated menu bar "D" with waveform/spinner states |

### Models (5 files)

| File | Purpose |
|------|---------|
| `Models/Models.swift` | Speaker (you/them), Utterance, SessionRecord |
| `Models/ClientInfo.swift` | Client data parsed from vault markdown files |
| `Models/ClientRegistry.swift` | Scans vault directory, parses client files |
| `Models/DettoVaultConfig.swift` | .detto.yaml vault configuration |
| `Models/TranscriptStore.swift` | Observable utterance list + volatile preview text |

### Transcription (1 file)

| File | Purpose |
|------|---------|
| `Transcription/TranscriptionEngine.swift` | Dual-stream orchestrator: mic + system audio, VAD, ASR, diarization, speaker attribution |

### Audio (2 files)

| File | Purpose |
|------|---------|
| `Audio/MicCapture.swift` | AVAudioEngine mic tap, device enumeration |
| `Audio/SystemAudioCapture.swift` | ScreenCaptureKit system audio, SCStream delegate |

### Dictation (8 files)

| File | Purpose |
|------|---------|
| `Dictation/DictationController.swift` | Hotkey-triggered record/transcribe/inject pipeline |
| `Dictation/DictationState.swift` | Observable state (idle/loading/recording/transcribing) |
| `Dictation/HotkeyManager.swift` | CGEvent tap for global hotkeys, double-press detection |
| `Dictation/HotkeyTypes.swift` | HotkeyOption enum, CustomHotkeyCombo |
| `Dictation/TextInjector.swift` | Clipboard swap + Cmd+V paste + accessibility monitoring |
| `Dictation/AccessibilityObserver.swift` | AXObserver for paste completion detection |
| `Dictation/AudioFeedbackManager.swift` | Start/stop sounds |
| `Dictation/LiveTranscriptionPanel.swift` | Floating pill overlay during dictation |

### Storage (2 files)

| File | Purpose |
|------|---------|
| `Storage/SessionStore.swift` | Actor, appends SessionRecords to JSONL files |
| `Storage/TranscriptLogger.swift` | Actor, writes markdown transcripts with YAML frontmatter |

### Settings (1 file)

| File | Purpose |
|------|---------|
| `Settings/AppSettings.swift` | UserDefaults-backed settings, security-scoped bookmarks |

### Views (10 files)

| File | Purpose |
|------|---------|
| `Views/ContentView.swift` | Main orchestrator view, wires TranscriptionEngine + stores + UI |
| `Views/SettingsView.swift` | Settings form (audio, dictation, storage, privacy) |
| `Views/DettoTheme.swift` | Color tokens, custom fonts (Azeret Mono, Plus Jakarta Sans) |
| `Views/ControlBar.swift` | Start/stop buttons, status display |
| `Views/TranscriptView.swift` | Scrolling chat bubbles with speaker colors |
| `Views/WaveformView.swift` | Spectrum visualizer with peak hold |
| `Views/BriefingPanelView.swift` | Client info panel, context editing |
| `Views/ClientGridView.swift` | Client card grid with selection |
| `Views/CheckForUpdatesView.swift` | Sparkle update button |
| `Views/OnboardingView.swift` | 4-step permission + model setup wizard |

## gremble-voice integration points

Detto imports three products from gremble-voice:

| Product | Used by | Purpose |
|---------|---------|---------|
| GrembleVoiceCore | TranscriptionEngine | Types: TranscriptionResult, DiarizedSegment, StreamingConfig |
| GrembleVoiceParakeet | TranscriptionEngine | ParakeetModelManager, ParakeetStreamingEngine, StreamingDiarizationEngine, VADProcessor |
| GrembleVoiceEngine | DictationController | GrembleVoicePipeline, PipelineConfig (3-stage: ASR + Dictionary + Refinement) |

## gremble-voice internal structure

| Module | Key actors/types | External dep |
|--------|-----------------|--------------|
| Core | Protocols (ASREngine, StreamingASREngine, AudioSource, TextRefiner), value types, text processing | None |
| Parakeet | ParakeetEngine, ParakeetStreamingEngine, ParakeetModelManager, DiarizationEngine, StreamingDiarizationEngine, VADProcessor | FluidAudio |
| Whisper | WhisperEngine, WhisperStreamingEngine, WhisperModelManager | WhisperKit |
| Audio | MicCaptureSource, AudioFileSource | AVFoundation |
| Refinement | MLXRefiner, OllamaRefiner, SmartRouter | MLX Swift |
| Cloud | OpenAI/Deepgram/Groq transcribers, Claude/OpenAI/Groq refiners | URLSession |
| Engine | GrembleVoicePipeline (observable, @MainActor) | All above |

## Build and release pipeline

```
PR to main --> build-check.yml --> swift build (validation only)

Release tag --> release-dmg.yml:
  1. swift build -c release
  2. build_swift_app.sh (bundle + sign + Metal shaders)
  3. make_dmg.sh (DMG + sign + notarize)
  4. Upload artifact + attach to release
  5. Sign DMG with Sparkle EdDSA, generate appcast.xml, push to gh-pages
```

## Key entitlements

- `com.apple.security.device.audio-input` -- mic access
- `com.apple.security.device.screen-capture` -- system audio via ScreenCaptureKit
- `com.apple.security.files.bookmarks.app-scope` -- vault file access
