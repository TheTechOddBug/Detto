@preconcurrency import AVFoundation
import CoreAudio
import GrembleVoiceCore
import GrembleVoiceParakeet
import Observation
import os

func engineLog(_ msg: String) {
    FileLogger.shared.log(msg, category: "engine")
}

enum TranscriptionError: Error { case notReady }

// MARK: - Audio Buffer Resampler

final class AudioBufferResampler: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func resample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        if sourceFormat.commonFormat == .pcmFormatFloat32 && sourceFormat.sampleRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error != nil { return nil }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}

// MARK: - Transcription Engine

/// Dual-stream mic + system audio transcription with real-time speaker diarization.
@Observable
@MainActor
final class TranscriptionEngine {
    private(set) var isRunning = false
    var assetStatus: String = "Ready"
    var lastError: String?

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicCapture()
    private let transcriptStore: TranscriptStore

    /// Combined audio level from mic and system for the UI meter.
    var audioLevel: Float { max(micCapture.audioLevel, systemCapture.audioLevel) }

    // GrembleVoice engines
    private var modelManager: ParakeetModelManager?
    private var asrEngine: ParakeetStreamingEngine?
    private var diarEngine: StreamingDiarizationEngine?
    private var offlineDiarEngine: DiarizationEngine?
    private var diarFailed = false

    private var corrector: VocabularyCorrector?

    // Post-session batch diarization
    private var sessionStartTime: Date?
    private var sysAudioFileHandle: FileHandle?
    private var sysAudioFilePath: URL?

    // Tasks
    private var micReaderTask: Task<Void, Never>?
    private var micTranscribeTask: Task<Void, Never>?
    private var sysLoopTask: Task<Void, Never>?
    private var diarUpdateTask: Task<Void, Never>?
    /// Keeps the mic stream alive for the audio level meter when transcription isn't running.
    private var micKeepAliveTask: Task<Void, Never>?
    private var deviceRestartTask: Task<Void, Never>?

    // Diarization state — updated from diarization update stream, read during attribution
    private var currentDiarSegments: [DiarizedSegment] = []

    /// Tracks the resolved mic device ID currently in use.
    private var currentMicDeviceID: AudioDeviceID = 0

    /// Tracks whether user selected "System Default" (0) or a specific device.
    private var userSelectedDeviceID: AudioDeviceID = 0

    /// Listens for default input device changes at the OS level.
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
    }

    func preloadModels() async {
        guard modelManager == nil else { return }
        let preloadStart = Date()
        engineLog("[ENGINE-PRELOAD] preloading models in background...")
        let mm = ParakeetModelManager()
        let diar = StreamingDiarizationEngine(preset: .highContext)
        engineLog("[ENGINE-DIAR] Streaming preset: highContext (30000 frames)")
        let offlineDiar = DiarizationEngine()

        do {
            async let asrLoad: Void = mm.loadModel { [weak self] progress in
                Task { @MainActor in
                    if progress < 0.9 {
                        self?.assetStatus = "Downloading ASR model... \(Int(progress * 100))%"
                    }
                }
            }
            async let diarLoad: Void = diar.prepareModels { _ in }
            async let offlineLoad: Void = offlineDiar.prepareModels()

            try await asrLoad
            self.modelManager = mm
            self.asrEngine = ParakeetStreamingEngine(modelManager: mm)

            do {
                try await diarLoad
                self.diarEngine = diar
            } catch {
                engineLog("[ENGINE-PRELOAD-WARN] Diarization model failed: \(error.localizedDescription)")
                diarFailed = true
            }

            do {
                try await offlineLoad
                self.offlineDiarEngine = offlineDiar
            } catch {
                engineLog("[ENGINE-PRELOAD-WARN] Offline diarization model failed: \(error.localizedDescription)")
            }

            assetStatus = "Ready"
            engineLog("[ENGINE-PRELOAD] models ready (\(String(format: "%.1f", Date().timeIntervalSince(preloadStart)))s)")
        } catch {
            engineLog("[ENGINE-PRELOAD-FAIL] \(error.localizedDescription)")
        }
    }

    func start(locale: Locale, inputDeviceID: AudioDeviceID = 0, appBundleID: String? = nil, micOnly: Bool = false, vocabularyCorrector: VocabularyCorrector? = nil) async {
        engineLog("[ENGINE-0] start() called, isRunning=\(isRunning)")
        guard !isRunning else { return }
        lastError = nil

        guard await ensureMicrophonePermission() else { return }

        isRunning = true
        self.corrector = vocabularyCorrector
        if let c = vocabularyCorrector {
            engineLog("[ENGINE-VOCAB] Corrector: \(c.termCount) terms, \(c.correctionCount) corrections")
        } else {
            engineLog("[ENGINE-VOCAB] No corrector")
        }

        // 1. Load GrembleVoice models if not already preloaded
        if modelManager == nil {
            let mm = ParakeetModelManager()
            let diar = StreamingDiarizationEngine(preset: .highContext)
            engineLog("[ENGINE-DIAR] Streaming preset: highContext (30000 frames)")

            assetStatus = "Loading models..."
            let modelLoadStart = Date()
            engineLog("[ENGINE-1] loading GrembleVoice models...")
            do {
                async let asrLoad: Void = mm.loadModel { [weak self] progress in
                    Task { @MainActor in
                        if progress < 0.9 {
                            self?.assetStatus = "Downloading ASR model... \(Int(progress * 100))%"
                        }
                    }
                }
                async let diarLoad: Void = diar.prepareModels { _ in }

                try await asrLoad
                self.modelManager = mm
                self.asrEngine = ParakeetStreamingEngine(modelManager: mm)

                do {
                    try await diarLoad
                    self.diarEngine = diar
                    engineLog("[ENGINE-1b] diarization models loaded")
                } catch {
                    engineLog("[ENGINE-1b-WARN] Diarization model failed: \(error.localizedDescription). Falling back to 'Them'.")
                    diarFailed = true
                }

                assetStatus = "Models ready"
                engineLog("[ENGINE-2] GrembleVoice models loaded (\(String(format: "%.1f", Date().timeIntervalSince(modelLoadStart)))s)")
            } catch {
                let msg = "Failed to load models: \(error.localizedDescription)"
                engineLog("[ENGINE-2-FAIL] \(msg)")
                lastError = msg
                assetStatus = "Ready"
                isRunning = false
                return
            }
        }

        guard let asrEngine else { return }

        // 2. Start mic capture
        userSelectedDeviceID = inputDeviceID
        let micDeviceParam: AudioDeviceID? = inputDeviceID > 0 ? inputDeviceID : nil
        currentMicDeviceID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID() ?? 0
        engineLog("[ENGINE-3] starting mic capture, deviceParam=\(String(describing: micDeviceParam)) tracked=\(currentMicDeviceID)")
        let micStream = micCapture.bufferStream(deviceID: micDeviceParam)
        if let captureError = micCapture.captureError {
            lastError = captureError
        }

        // 3. Start system audio capture (skipped for mic-only mode)
        engineLog("[ENGINE-4] starting system audio capture...")
        let sysStreams: SystemAudioCapture.CaptureStreams?
        if micOnly {
            engineLog("[ENGINE-4-SKIP] System audio capture skipped (mic-only mode)")
            sysStreams = nil
        } else if !CGPreflightScreenCaptureAccess() {
            engineLog("[ENGINE-4-NOPERM] Screen Recording permission not granted")
            lastError = "Screen Recording access required for system audio. Enable it in System Settings > Privacy & Security > Screen Recording."
            sysStreams = nil
        } else {
            do {
                sysStreams = try await systemCapture.bufferStream(appBundleID: appBundleID)
                engineLog("[ENGINE-5] system audio capture started OK")
            } catch {
                let msg = "Failed to start system audio: \(error.localizedDescription)"
                engineLog("[ENGINE-5-FAIL] \(msg)")
                lastError = msg
                sysStreams = nil
            }
        }

        // 4. Start mic transcription pipeline (VADProcessor — no timing needed)
        let store = transcriptStore
        do {
            guard let modelManager else { throw TranscriptionError.notReady }
            let micVadManager = try await modelManager.makeVadManager()
            let micVad = VADProcessor(vadManager: micVadManager)
            let micResampler = AudioBufferResampler()

            let (micSampleStream, micSampleCont) = AsyncStream<[Float]>.makeStream()
            micReaderTask = Task.detached {
                for await buffer in micStream {
                    guard let samples = micResampler.resample(buffer) else { continue }
                    micSampleCont.yield(samples)
                }
                micSampleCont.finish()
            }

            let asr = asrEngine
            let vocabCorrector = self.corrector
            let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }
            micTranscribeTask = Task.detached {
                let hadFatalError = await micVad.run(stream: micSampleStream) { segment in
                    engineLog("[MIC] VAD segment: \(segment.count) samples (\(String(format: "%.1f", Double(segment.count) / 16000))s)")
                    let asrStart = Date()
                    guard let result = try? await asr.transcribe(samples: segment, source: .microphone) else {
                        engineLog("[MIC] ASR returned nil")
                        return
                    }
                    let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let corrected = vocabCorrector?.correct(rawText)
                    let text = corrected?.text ?? rawText
                    if let corrected, !corrected.corrections.isEmpty {
                        for c in corrected.corrections {
                            engineLog("[VOCAB] \(c.rule): \"\(c.original)\" -> \"\(c.corrected)\"")
                        }
                    }
                    let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
                    guard !text.isEmpty else {
                        engineLog("[MIC] ASR returned empty text (\(asrMs)ms)")
                        return
                    }
                    engineLog("[MIC] utterance: \(text.count) chars, \(asrMs)ms, conf=\(String(format: "%.2f", result.confidence ?? 0))")
                    let confidence = result.confidence
                    Task { @MainActor in
                        store.volatileYouText = ""
                        store.append(Utterance(text: text, speaker: .you, speakerName: "You", confidence: confidence))
                    }
                }
                if hadFatalError {
                    reportMicError("Mic transcription failed — restart session")
                }
            }
        } catch {
            engineLog("[ENGINE-4-FAIL] Mic VAD setup failed: \(error.localizedDescription)")
            lastError = "Mic setup failed: \(error.localizedDescription)"
        }

        // 5. Start system audio pipeline (inline VAD + diarization)
        if let sysStream = sysStreams?.systemAudio {
            sessionStartTime = Date()

            // Start diarization session if available
            if let diarEngine {
                do {
                    try await diarEngine.startSession()
                    diarUpdateTask = Task { @MainActor [weak self] in
                        for await update in await diarEngine.updates {
                            self?.currentDiarSegments = update.finalizedSegments + update.tentativeSegments
                        }
                    }
                } catch {
                    engineLog("[ENGINE-5b-WARN] Diarization session start failed: \(error.localizedDescription)")
                    diarFailed = true
                }
            }

            // Create temp audio file for post-session batch diarization
            if offlineDiarEngine != nil {
                let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("io.gremble.detto/audio-sessions", isDirectory: true)
                try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                let audioPath = cachesDir.appendingPathComponent("\(UUID().uuidString).raw")
                FileManager.default.createFile(atPath: audioPath.path, contents: nil)
                sysAudioFilePath = audioPath
                sysAudioFileHandle = try? FileHandle(forWritingTo: audioPath)
                engineLog("[ENGINE-5c] Temp audio file created: \(audioPath.lastPathComponent)")
            }

            let sysResampler = AudioBufferResampler()
            let asr = asrEngine
            let diarRef = diarEngine
            let diarAvailable = !diarFailed
            let audioHandle = sysAudioFileHandle
            let sysVocabCorrector = self.corrector
            let reportSysError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }

            do {
                guard let modelManager else { throw TranscriptionError.notReady }
                let sysVadManager = try await modelManager.makeVadManager(threshold: 0.92)

                sysLoopTask = Task.detached { [weak self] in
                    var vadState = await sysVadManager.makeStreamState()
                    var speechSamples: [Float] = []
                    var vadBuffer: [Float] = []
                    var isSpeaking = false
                    var consecutiveErrors = 0
                    var totalSampleOffset = 0
                    var speechStartOffset = 0

                    for await buffer in sysStream {
                        guard let samples = sysResampler.resample(buffer) else { continue }

                        if diarAvailable {
                            await diarRef?.addAudio(samples)
                        }

                        if let handle = audioHandle {
                            samples.withUnsafeBufferPointer { ptr in
                                if let base = ptr.baseAddress {
                                    let data = Data(bytes: base, count: ptr.count * MemoryLayout<Float>.size)
                                    handle.write(data)
                                }
                            }
                        }

                        vadBuffer.append(contentsOf: samples)

                        while vadBuffer.count >= 4096 {
                            let chunk = Array(vadBuffer.prefix(4096))
                            vadBuffer.removeFirst(4096)
                            totalSampleOffset += 4096

                            do {
                                let result = try await sysVadManager.processStreamingChunk(
                                    chunk,
                                    state: vadState,
                                    config: .default,
                                    returnSeconds: true,
                                    timeResolution: 2
                                )
                                vadState = result.state
                                consecutiveErrors = 0

                                if let event = result.event {
                                    switch event.kind {
                                    case .speechStart:
                                        isSpeaking = true
                                        speechSamples.removeAll(keepingCapacity: true)
                                        speechStartOffset = totalSampleOffset
                                        engineLog("[SYS] speech start")

                                    case .speechEnd:
                                        isSpeaking = false
                                        engineLog("[SYS] speech end, \(speechSamples.count) samples (\(String(format: "%.1f", Double(speechSamples.count) / 16000))s)")
                                        if speechSamples.count >= 8_000 {
                                            let segment = speechSamples
                                            let startT = TimeInterval(speechStartOffset) / 16000.0
                                            let endT = TimeInterval(totalSampleOffset) / 16000.0
                                            speechSamples.removeAll(keepingCapacity: true)
                                            await Self.transcribeAndAttribute(
                                                segment: segment, startTime: startT, endTime: endT,
                                                asr: asr, store: store, engine: self,
                                                diarAvailable: diarAvailable,
                                                corrector: sysVocabCorrector
                                            )
                                        } else {
                                            engineLog("[SYS] segment too short (\(speechSamples.count) samples), discarded")
                                            speechSamples.removeAll(keepingCapacity: true)
                                        }
                                    }
                                }

                                if isSpeaking {
                                    speechSamples.append(contentsOf: chunk)
                                    if speechSamples.count >= 480_000 {
                                        engineLog("[SYS] 30s forced split, flushing segment")
                                        let segment = speechSamples
                                        let startT = TimeInterval(speechStartOffset) / 16000.0
                                        let endT = TimeInterval(totalSampleOffset) / 16000.0
                                        speechSamples.removeAll(keepingCapacity: true)
                                        speechStartOffset = totalSampleOffset
                                        await Self.transcribeAndAttribute(
                                            segment: segment, startTime: startT, endTime: endT,
                                            asr: asr, store: store, engine: self,
                                            diarAvailable: diarAvailable,
                                            corrector: sysVocabCorrector
                                        )
                                    }
                                }
                            } catch {
                                consecutiveErrors += 1
                                engineLog("[SYS] VAD error #\(consecutiveErrors): \(error.localizedDescription)")
                                if consecutiveErrors > 10 {
                                    reportSysError("System audio transcription failed — restart session")
                                    break
                                }
                            }
                        }
                    }

                    // Flush trailing speech
                    if speechSamples.count >= 8_000 {
                        engineLog("[SYS] flushing trailing speech: \(speechSamples.count) samples")
                        let startT = TimeInterval(speechStartOffset) / 16000.0
                        let endT = TimeInterval(totalSampleOffset) / 16000.0
                        await Self.transcribeAndAttribute(
                            segment: speechSamples, startTime: startT, endTime: endT,
                            asr: asr, store: store, engine: self,
                            diarAvailable: diarAvailable,
                            corrector: sysVocabCorrector
                        )
                    }
                }
            } catch {
                engineLog("[ENGINE-5c-FAIL] System VAD setup failed: \(error.localizedDescription)")
                lastError = "System audio setup failed: \(error.localizedDescription)"
            }
        }

        assetStatus = "Transcribing (Parakeet-TDT v3)"
        engineLog("[ENGINE-6] all transcription tasks started")

        installDefaultDeviceListener()
    }

    /// Restart only the mic capture with a new device, keeping system audio and models intact.
    func restartMic(inputDeviceID: AudioDeviceID) {
        guard isRunning, let modelManager, let asrEngine else { return }

        if inputDeviceID != 0 || userSelectedDeviceID != 0 {
            userSelectedDeviceID = inputDeviceID
        }
        let resolvedMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID() ?? 0
        guard resolvedMicID != currentMicDeviceID else {
            engineLog("[ENGINE-MIC-SWAP] same device \(resolvedMicID), skipping")
            return
        }

        engineLog("[ENGINE-MIC-SWAP] switching mic from \(currentMicDeviceID) to \(resolvedMicID)")

        micReaderTask?.cancel()
        micTranscribeTask?.cancel()
        micReaderTask = nil
        micTranscribeTask = nil
        micCapture.stop()

        currentMicDeviceID = resolvedMicID

        let micDeviceParam: AudioDeviceID? = inputDeviceID > 0 ? inputDeviceID : nil
        let micStream = micCapture.bufferStream(deviceID: micDeviceParam)
        if let captureError = micCapture.captureError {
            lastError = captureError
        }
        let store = transcriptStore
        let asr = asrEngine
        let micResampler = AudioBufferResampler()

        let (micSampleStream, micSampleCont) = AsyncStream<[Float]>.makeStream()
        micReaderTask = Task.detached {
            for await buffer in micStream {
                guard let samples = micResampler.resample(buffer) else { continue }
                micSampleCont.yield(samples)
            }
            micSampleCont.finish()
        }

        Task {
            guard let micVadManager = try? await modelManager.makeVadManager() else {
                engineLog("[ENGINE-MIC-SWAP] VAD creation failed")
                return
            }
            let micVad = VADProcessor(vadManager: micVadManager)

            let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }
            self.micTranscribeTask = Task.detached {
                let hadFatalError = await micVad.run(stream: micSampleStream) { segment in
                    engineLog("[MIC] VAD segment: \(segment.count) samples (\(String(format: "%.1f", Double(segment.count) / 16000))s)")
                    let asrStart = Date()
                    guard let result = try? await asr.transcribe(samples: segment, source: .microphone) else {
                        engineLog("[MIC] ASR returned nil")
                        return
                    }
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
                    guard !text.isEmpty else {
                        engineLog("[MIC] ASR returned empty text (\(asrMs)ms)")
                        return
                    }
                    engineLog("[MIC] utterance: \(text.count) chars, \(asrMs)ms, conf=\(String(format: "%.2f", result.confidence ?? 0))")
                    let confidence = result.confidence
                    Task { @MainActor in
                        store.volatileYouText = ""
                        store.append(Utterance(text: text, speaker: .you, speakerName: "You", confidence: confidence))
                    }
                }
                if hadFatalError {
                    reportMicError("Mic transcription failed — restart session")
                }
            }
        }

        engineLog("[ENGINE-MIC-SWAP] mic restarted on device \(resolvedMicID)")

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard self.isRunning, !self.micCapture.tapIsActive else { return }
            engineLog("[ENGINE-MIC-WATCHDOG] No mic activity 3s after restart")
            self.lastError = "Microphone disconnected. System audio continues."
        }
    }

    // MARK: - Speaker Attribution

    private nonisolated static func transcribeAndAttribute(
        segment: [Float],
        startTime: TimeInterval,
        endTime: TimeInterval,
        asr: ParakeetStreamingEngine,
        store: TranscriptStore,
        engine: TranscriptionEngine?,
        diarAvailable: Bool,
        corrector: VocabularyCorrector? = nil
    ) async {
        let duration = endTime - startTime
        let asrStart = Date()
        guard let result = try? await asr.transcribe(samples: segment, source: .system) else {
            engineLog("[SYS-ASR] transcribe returned nil for \(String(format: "%.1f", duration))s segment")
            return
        }
        let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = corrector?.correct(rawText)
        let text = corrected?.text ?? rawText
        if let corrected, !corrected.corrections.isEmpty {
            for c in corrected.corrections {
                engineLog("[VOCAB] \(c.rule): \"\(c.original)\" -> \"\(c.corrected)\"")
            }
        }
        let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
        guard !text.isEmpty else {
            engineLog("[SYS-ASR] empty text for \(String(format: "%.1f", duration))s segment (\(asrMs)ms)")
            return
        }

        let midpoint = (startTime + endTime) / 2
        let speakerName: String
        var attributionMethod = "none"
        if diarAvailable {
            speakerName = await MainActor.run {
                guard let engine else { return "Them" }
                if let seg = engine.currentDiarSegments.first(where: {
                    $0.startTime <= midpoint && midpoint <= $0.endTime
                }) {
                    attributionMethod = "direct"
                    return seg.speaker.displayName
                }
                if let closest = engine.currentDiarSegments.min(by: {
                    abs(($0.startTime + $0.endTime) / 2 - midpoint) <
                    abs(($1.startTime + $1.endTime) / 2 - midpoint)
                }), abs((closest.startTime + closest.endTime) / 2 - midpoint) < 10 {
                    attributionMethod = "closest"
                    return closest.speaker.displayName
                }
                attributionMethod = "fallback"
                return "Them"
            }
        } else {
            speakerName = "Them"
        }

        engineLog("[SYS-ASR] \(text.count) chars, \(asrMs)ms, conf=\(String(format: "%.2f", result.confidence ?? 0)), speaker=\"\(speakerName)\" (\(attributionMethod)), segment=\(String(format: "%.1f", duration))s")

        let confidence = result.confidence
        Task { @MainActor in
            store.volatileThemText = ""
            store.append(Utterance(text: text, speaker: .them, speakerName: speakerName, confidence: confidence))
        }
    }

    // MARK: - Default Device Listener

    private func installDefaultDeviceListener() {
        guard defaultDeviceListenerBlock == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let newDefault = MicCapture.defaultInputDeviceID() ?? 0
            engineLog("[ENGINE-DEVICE] OS default input device changed to \(newDefault)")
            Task { @MainActor in
                guard self.isRunning else { return }
                if self.userSelectedDeviceID != 0 {
                    let stillAvailable = MicCapture.availableInputDevices().contains { $0.id == self.userSelectedDeviceID }
                    if stillAvailable { return }
                    engineLog("[ENGINE-DEVICE] Selected device \(self.userSelectedDeviceID) disconnected, falling back to default")
                    self.userSelectedDeviceID = 0
                }
                self.deviceRestartTask?.cancel()
                self.deviceRestartTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self.restartMic(inputDeviceID: 0)
                }
            }
        }
        defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        deviceRestartTask?.cancel()
        deviceRestartTask = nil
        defaultDeviceListenerBlock = nil
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                assetStatus = "Ready"
            }
            return granted
        case .denied, .restricted:
            lastError = "Microphone access is disabled. Enable it in System Settings > Privacy & Security > Microphone."
            assetStatus = "Ready"
            return false
        @unknown default:
            lastError = "Unable to verify microphone permission."
            assetStatus = "Ready"
            return false
        }
    }

    func stop() async {
        engineLog("[ENGINE-STOP] stop() called, cancelling all tasks")
        isRunning = false

        await systemCapture.stop()
        micCapture.stop()

        micReaderTask?.cancel()
        micTranscribeTask?.cancel()
        sysLoopTask?.cancel()
        diarUpdateTask?.cancel()
        micKeepAliveTask?.cancel()
        micReaderTask = nil
        micTranscribeTask = nil
        sysLoopTask = nil
        diarUpdateTask = nil
        micKeepAliveTask = nil

        removeDefaultDeviceListener()

        sysAudioFileHandle?.closeFile()
        sysAudioFileHandle = nil

        if let diarEngine {
            _ = try? await diarEngine.stopSession()
        }

        corrector = nil
        lastError = nil
        currentMicDeviceID = 0
        currentDiarSegments = []
        assetStatus = "Ready"
        engineLog("[ENGINE-STOP] stop() complete")
    }

    // MARK: - Post-session batch diarization

    func runOfflineDiarization() async {
        guard let audioPath = sysAudioFilePath else { return }
        guard let engine = offlineDiarEngine, await engine.isReady else {
            cleanupTempAudio()
            return
        }

        let hasRemoteUtterances = transcriptStore.utterances.contains { $0.speaker == .them }
        if !hasRemoteUtterances {
            engineLog("[OFFLINE-DIAR] Skipping batch pass (no remote utterances)")
            cleanupTempAudio()
            return
        }

        engineLog("[OFFLINE-DIAR] Starting batch pass on \(audioPath.lastPathComponent)")

        do {
            let data = try Data(contentsOf: audioPath)
            let samples = data.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }

            let result = try await engine.process(samples: samples)
            applyOfflineSpeakerLabels(result)
            engineLog("[OFFLINE-DIAR] Batch pass complete, \(result.count) segments")
        } catch {
            engineLog("[OFFLINE-DIAR] Batch pass failed: \(error.localizedDescription)")
        }

        cleanupTempAudio()
    }

    private func applyOfflineSpeakerLabels(_ segments: [DiarizationEngine.Segment]) {
        guard let startTime = sessionStartTime else { return }

        for i in transcriptStore.utterances.indices {
            let utterance = transcriptStore.utterances[i]
            guard utterance.speaker == .them else { continue }

            let offsetSeconds = Float(utterance.timestamp.timeIntervalSince(startTime))
            if let match = segments.first(where: {
                $0.startTime <= offsetSeconds && offsetSeconds <= $0.endTime
            }) {
                transcriptStore.updateSpeakerName(at: i, name: "Speaker \(Self.parseSpeakerIndex(match.speakerId) + 1)")
            } else {
                let nearest = segments.min(by: {
                    min(abs($0.startTime - offsetSeconds), abs($0.endTime - offsetSeconds)) <
                    min(abs($1.startTime - offsetSeconds), abs($1.endTime - offsetSeconds))
                })
                if let nearest {
                    let gap = min(abs(nearest.startTime - offsetSeconds), abs(nearest.endTime - offsetSeconds))
                    if gap <= 5.0 {
                        transcriptStore.updateSpeakerName(at: i, name: "Speaker \(Self.parseSpeakerIndex(nearest.speakerId) + 1)")
                    }
                }
            }
        }
    }

    private static func parseSpeakerIndex(_ speakerId: String) -> Int {
        if let range = speakerId.range(of: #"\d+$"#, options: .regularExpression),
           let idx = Int(speakerId[range]) {
            return idx
        }
        return 0
    }

    private func cleanupTempAudio() {
        if let path = sysAudioFilePath {
            try? FileManager.default.removeItem(at: path)
        }
        sysAudioFilePath = nil
        sessionStartTime = nil
    }

    static func cleanupOrphanedAudioFiles() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("io.gremble.detto/audio-sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
