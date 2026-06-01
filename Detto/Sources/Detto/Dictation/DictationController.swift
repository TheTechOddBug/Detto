import Foundation
import GrembleVoiceCore
import GrembleVoiceEngine

@MainActor
final class DictationController {

    // MARK: - Components

    private let hotkeyManager = HotkeyManager()
    private let textInjector = TextInjector()
    private let audioFeedback = AudioFeedbackManager.shared

    // MARK: - GrembleVoice pipeline

    let pipeline: GrembleVoicePipeline

    // MARK: - State

    let state = DictationState()

    // MARK: - Overlay

    private var liveOverlayController: LiveTranscriptionPanelController?
    private var recordingDurationTimer: Timer?
    private var audioLevelTimer: Timer?

    // MARK: - Recording lifecycle

    private var pipelineStartTask: Task<Void, Error>?
    private var pendingStop = false

    // MARK: - Mutual exclusion

    var isMeetingActive: () -> Bool = { false }

    // MARK: - Init

    init() {
        pipeline = GrembleVoicePipeline(config: DictationController.makeConfig())
    }

    // MARK: - Config

    static func makeConfig() -> PipelineConfig {
        PipelineConfig(
            asrEngine: .parakeet,
            refiner: .mlx(),
            dictionaryEntries: [],
            language: "en"
        )
    }

    // MARK: - Hotkey passthrough

    func updateHotkey(_ option: HotkeyOption) {
        hotkeyManager.updateHotkey(option)
        configureHotkeyCallbacks()
    }

    func updateToggleMode(_ isToggle: Bool) {
        hotkeyManager.updateToggleMode(isToggle)
        configureHotkeyCallbacks()
    }

    func suspendHotkey() { hotkeyManager.suspend() }
    func resumeHotkey()  { hotkeyManager.resume() }

    // MARK: - Model loading

    private let log = FileLogger.shared

    func loadModel() async throws {
        state.recordingState = .loadingModel
        state.modelDownloadProgress = 0
        state.lastError = nil
        log.log("Starting model load (config: \(Self.makeConfig().asrEngine.displayName), refiner: \(Self.makeConfig().refiner))", category: "model")
        do {
            try await pipeline.loadModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state.modelDownloadProgress = progress
                }
            }
            state.isModelLoaded = true
            state.recordingState = .idle
            log.log("Model loaded successfully", category: "model")
        } catch {
            state.recordingState = .idle
            state.modelDownloadProgress = 0
            log.log("Model loading failed: \(error)", category: "model")
            throw error
        }
    }

    // MARK: - Lifecycle

    @discardableResult
    func startHotkeys() -> Bool {
        guard hotkeyManager.start() else { return false }
        state.hasAccessibilityPermission = true
        configureHotkeyCallbacks()
        return true
    }

    func start() async throws {
        if !state.isModelLoaded {
            try await loadModel()
        }
        guard hotkeyManager.start() else {
            throw DictationError.accessibilityDenied
        }
        state.hasAccessibilityPermission = true
        configureHotkeyCallbacks()
    }

    func stop() {
        hotkeyManager.stop()
        if pipeline.isRecording {
            Task { try? await pipeline.stopRecording() }
        }
        dismissOverlay()
    }

    // MARK: - Hotkey callbacks

    private func configureHotkeyCallbacks() {
        if HotkeyOption.isToggleMode {
            hotkeyManager.onKeyDown = nil
            hotkeyManager.onKeyUp = nil
            hotkeyManager.onToggle = { [weak self] isRecording in
                if isRecording { self?.startRecordingWithFeedback() }
                else           { self?.stopRecordingAndTranscribeWithFeedback() }
            }
        } else {
            hotkeyManager.onToggle = nil
            hotkeyManager.onKeyDown = { [weak self] in self?.startRecording() }
            hotkeyManager.onKeyUp   = { [weak self] in self?.stopRecordingAndTranscribe() }
        }
    }

    private func startRecordingWithFeedback() {
        audioFeedback.playRecordingStart()
        startRecording()
    }

    private func stopRecordingAndTranscribeWithFeedback() {
        audioFeedback.playRecordingStop()
        stopRecordingAndTranscribe()
    }

    // MARK: - Recording

    private func startRecording() {
        guard state.recordingState == .idle else { return }
        guard !isMeetingActive() else { return }

        log.log("Recording started", category: "dictation")
        state.recordingState = .recording
        state.recordingDuration = 0
        state.lastDictationJustFinished = false
        pendingStop = false

        let startTime = Date()
        recordingDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.state.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }

        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.audioLevel = self.pipeline.audioLevel
            }
        }

        showOverlay()

        pipelineStartTask = Task { [weak self] in
            guard let self else { return }
            try await pipeline.startRecording()
            if self.pendingStop {
                self.pendingStop = false
                self.performStop()
            }
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.pipelineStartTask?.value
            } catch {
                self.pipelineStartTask = nil
                self.pendingStop = false
                self.log.log("Failed to start recording: \(error)", category: "dictation")
                self.state.lastError = "Failed to start recording: \(error.localizedDescription)"
                self.state.recordingState = .idle
                self.hotkeyManager.resetToggleState()
                self.dismissOverlay()
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state.recordingState == .recording else { return }

        if !pipeline.isRecording {
            pendingStop = true
            return
        }

        performStop()
    }

    private func performStop() {
        recordingDurationTimer?.invalidate()
        recordingDurationTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        state.audioLevel = 0
        state.recordingState = .transcribing
        pipelineStartTask = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await pipeline.stopRecording()

                let text = session.refinedText
                let injectText = " " + (text.isEmpty ? session.rawTranscript : text)

                let fallback = session.isRefinementFallback ? " FALLBACK(\(session.fallbackReason ?? "?"))" : ""
                let pipelineMs = session.totalPipelineMs
                self.log.log("Transcription complete (\(pipelineMs)ms\(fallback)): \(session.rawTranscript.count) chars raw, \(text.count) chars refined", category: "dictation")

                self.state.recordingState = .idle
                self.state.lastDictationJustFinished = true

                await textInjector.inject(text: injectText)

                self.liveOverlayController?.showDone()
            } catch {
                self.log.log("Transcription failed: \(error)", category: "dictation")
                self.state.lastError = "Transcription failed: \(error.localizedDescription)"
                self.dismissOverlay()
                self.state.recordingState = .idle
                self.hotkeyManager.resetToggleState()
            }
        }
    }

    // MARK: - Overlay

    private func showOverlay() {
        if liveOverlayController == nil {
            liveOverlayController = LiveTranscriptionPanelController(state: state)
        }
        liveOverlayController?.show()
    }

    private func dismissOverlay() {
        liveOverlayController?.dismiss()
        state.audioLevel = 0
        state.lastDictationJustFinished = false
        state.recordingDuration = 0
    }
}

// MARK: - Errors

enum DictationError: Error {
    case accessibilityDenied
    case microphoneDenied
    case modelNotLoaded
}
