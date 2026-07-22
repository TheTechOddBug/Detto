import SwiftUI
import AppKit
import Combine
import GrembleVoiceParakeet

private let conferencingBundleIDs: [String: String] = [
    "com.microsoft.teams2": "Teams",
    "com.microsoft.teams": "Teams",
    "us.zoom.xos": "Zoom",
    "com.apple.FaceTime": "FaceTime",
    "com.tinyspeck.slackmacgap": "Slack",
    "com.cisco.webexmeetingsapp": "Webex",
    "Cisco-Systems.Spark": "Webex",
    "com.google.Chrome": "Chrome",
    "company.thebrowser.Browser": "Arc",
    "com.apple.Safari": "Safari",
    "com.microsoft.edgemac": "Edge",
]

struct ContentView: View {
    @Bindable var settings: AppSettings
    var dictationController: DictationController
    var asrManager: ParakeetModelManager
    @State private var transcriptStore = TranscriptStore()
    @State private var transcriptionEngine: TranscriptionEngine?
    @State private var sessionStore = SessionStore()
    @State private var transcriptLogger = TranscriptLogger()
    @State private var clientRegistry = ClientRegistry()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var audioLevel: Float = 0
    @State private var activeSessionType: SessionType?
    @State private var activeClient: ClientInfo?
    @State private var detectedAppName: String?
    @State private var silenceSeconds: Int = 0
    @State private var savedFileURL: URL?
    @State private var sessionElapsed: Int = 0
    @State private var editableContext: String = ""
    @State private var genericAttendees: String = ""
    @State private var contextUpdateTask: Task<Void, Never>?

    var body: some View {
        Group {
            if clientRegistry.hasClients {
                wideLayout
            } else {
                narrowLayout
            }
        }
        .background(Color.dBg)
        .overlay {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if dictationController.state.recordingState == .loadingModel && !showOnboarding {
                ModelDownloadBanner(progress: dictationController.state.modelDownloadProgress)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dictationController.state.recordingState)
        .onChange(of: showOnboarding) {
            if !showOnboarding {
                hasCompletedOnboarding = true
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
            if transcriptionEngine == nil {
                transcriptionEngine = TranscriptionEngine(transcriptStore: transcriptStore, modelManager: asrManager)
            }
            dictationController.isMeetingActive = { [weak transcriptionEngine] in
                transcriptionEngine?.isRunning ?? false
            }
            dictationController.startHotkeys()
            do {
                try await dictationController.loadModel()
            } catch {
                dictationController.state.lastError = "Model loading failed: \(error.localizedDescription)"
            }
            await transcriptionEngine?.preloadModels()
        }
        // Client scan on startup
        .task {
            if let vaultRoot = settings.vaultRootURL {
                await clientRegistry.scan(vaultRoot: vaultRoot)
            }
            if CommandLine.arguments.contains("-demo") {
                transcriptStore.loadDemoData()
                if let meridian = clientRegistry.allClients.first(where: { $0.name == "Meridian Labs" }) {
                    clientRegistry.selectedClient = meridian
                }
            }
        }
        // Re-scan when vault root changes
        .onChange(of: settings.vaultRootPath) {
            Task {
                if let vaultRoot = settings.vaultRootURL {
                    await clientRegistry.scan(vaultRoot: vaultRoot)
                }
            }
        }
        // Audio level polling
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let engine = transcriptionEngine else {
                    if audioLevel != 0 { audioLevel = 0 }
                    continue
                }
                if engine.isRunning {
                    let newLevel = engine.audioLevel
                    if abs(newLevel - audioLevel) > 0.005 { audioLevel = newLevel }
                    if audioLevel > 0.01 {
                        silenceSeconds = 0
                    }
                } else if audioLevel != 0 {
                    audioLevel = 0
                }
            }
        }
        // Silence auto-stop + elapsed timer
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning else {
                    silenceSeconds = 0
                    continue
                }
                sessionElapsed += 1
                if audioLevel < 0.01 {
                    silenceSeconds += 1
                    if silenceSeconds >= 120 {
                        stopSession()
                    }
                }
            }
        }
        // Transcript buffer flush
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await transcriptLogger.flushIfNeeded()
            }
        }
        .onChange(of: settings.inputDeviceID) {
            if isRunning {
                transcriptionEngine?.restartMic(inputDeviceID: settings.inputDeviceID)
            }
        }
        .onChange(of: transcriptStore.utterances.count) {
            handleNewUtterance()
        }
    }

    // MARK: - Wide Layout (clients available)

    private var wideLayout: some View {
        VStack(spacing: 0) {
            dettoToolbar
            Divider()

            HStack(spacing: 0) {
                ClientGridView(
                    clients: clientRegistry.topClients(count: 6),
                    moreClients: clientRegistry.remainingClients(afterTop: 6),
                    selectedClient: Binding(
                        get: { clientRegistry.selectedClient },
                        set: { clientRegistry.selectedClient = $0 }
                    ),
                    isRecording: isRunning
                )
                .frame(width: 220)

                Divider()

                wideRightContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .onChange(of: clientRegistry.selectedClient) {
            editableContext = ""
            guard !isRunning else { return }
            if let client = clientRegistry.selectedClient {
                genericAttendees = client.allParticipantNames.joined(separator: ", ")
            } else {
                genericAttendees = ""
            }
        }
        .overlay {
            VStack {
                Button("") {
                    if clientRegistry.selectedClient != nil {
                        startClientRecording()
                    } else {
                        startSession(type: .callCapture)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("") { startSession(type: .voiceMemo) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("") { stopSession() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var wideRightContent: some View {
        if isRunning && activeSessionType == .voiceMemo {
            VStack(spacing: 0) {
                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: ""
                )
                if let error = transcriptionEngine?.lastError {
                    Text(error).font(.dMono(size: 10, weight: .medium)).foregroundStyle(Color.dRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 2)
                }
                WaveformView(isRecording: true, audioLevel: audioLevel)
                wideStopBar
            }
        } else if isRunning {
            VStack(spacing: 0) {
                BriefingPanelView(
                    selectedClient: activeClient ?? clientRegistry.selectedClient,
                    isRecording: true,
                    silenceSeconds: silenceSeconds,
                    editableContext: $editableContext,
                    genericAttendees: $genericAttendees,
                    onStartCallCapture: { startSession(type: .callCapture) },
                    onStartVoiceMemo: { startSession(type: .voiceMemo) },
                    onStop: stopSession,
                    onContextChanged: { newContext in
                        contextUpdateTask?.cancel()
                        contextUpdateTask = Task {
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else { return }
                            await transcriptLogger.updateContext(newContext)
                        }
                    }
                )
                .frame(maxHeight: 200)

                Divider()

                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: transcriptStore.volatileThemText
                )

                if let error = transcriptionEngine?.lastError {
                    Text(error).font(.dMono(size: 10, weight: .medium)).foregroundStyle(Color.dRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 2)
                }

                WaveformView(isRecording: true, audioLevel: audioLevel)
                wideStopBar
            }
        } else if !transcriptStore.utterances.isEmpty {
            VStack(spacing: 0) {
                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: transcriptStore.volatileThemText
                )

                Divider()

                HStack {
                    Text(transcriptionEngine?.assetStatus ?? "Saving...")
                        .font(.dMono(size: 11, weight: .medium))
                        .foregroundStyle(Color.dDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                if let url = savedFileURL {
                    saveBanner(url: url)
                }
            }
        } else {
            VStack(spacing: 0) {
                if let url = savedFileURL {
                    saveBanner(url: url)
                }

                BriefingPanelView(
                    selectedClient: activeClient ?? clientRegistry.selectedClient,
                    isRecording: false,
                    silenceSeconds: silenceSeconds,
                    editableContext: $editableContext,
                    genericAttendees: $genericAttendees,
                    onStartCallCapture: { startSession(type: .callCapture) },
                    onStartVoiceMemo: { startSession(type: .voiceMemo) },
                    onStop: stopSession,
                    onContextChanged: { newContext in
                        contextUpdateTask?.cancel()
                        contextUpdateTask = Task {
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else { return }
                            await transcriptLogger.updateContext(newContext)
                        }
                    }
                )
            }
        }
    }

    private var wideStopBar: some View {
        VStack(spacing: 0) {
            Divider()
            if silenceSeconds >= 90 {
                Text("Silence \u{2014} auto-stop in \(120 - silenceSeconds)s")
                    .font(.dMono(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 4)
            }
            Button(action: stopSession) {
                HStack(spacing: 10) {
                    PulsingDot(size: 6)
                    Text("STOP RECORDING")
                        .font(.dMono(size: 12, weight: .bold))
                        .foregroundStyle(Color.dRed)
                    Spacer()
                    Text("\u{2318}.")
                        .font(.dMono(size: 10, weight: .medium))
                        .foregroundStyle(Color.dDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.dRed.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dRed, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Narrow Layout (no clients)

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            dettoToolbar
            Divider()

            if !isRunning && transcriptStore.utterances.isEmpty
                && transcriptStore.volatileYouText.isEmpty
                && transcriptStore.volatileThemText.isEmpty {
                emptyState
            } else {
                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: transcriptStore.volatileThemText
                )
            }

            if let url = savedFileURL, activeSessionType == nil {
                saveBanner(url: url)
            }

            WaveformView(isRecording: isRunning, audioLevel: audioLevel)

            ControlBar(
                isRecording: isRunning,
                activeSessionType: activeSessionType,
                audioLevel: audioLevel,
                detectedApp: detectedAppName,
                silenceSeconds: silenceSeconds,
                statusMessage: transcriptionEngine?.assetStatus,
                errorMessage: transcriptionEngine?.lastError,
                onStartCallCapture: { startSession(type: .callCapture) },
                onStartVoiceMemo: { startSession(type: .voiceMemo) },
                onStop: stopSession
            )
        }
        .frame(minWidth: 280, minHeight: 400)
    }

    // MARK: - Detto Toolbar

    private var dettoToolbar: some View {
        HStack(spacing: 0) {
            DettoWordmark(size: 18)

            Spacer()

            HStack(spacing: 10) {
                if isRunning {
                    if let client = activeClient ?? clientRegistry.selectedClient {
                        Text(client.name)
                            .font(.dMono(size: 11, weight: .semibold))
                            .foregroundStyle(Color.dSecondary)
                            .lineLimit(1)
                    } else if activeSessionType == .voiceMemo {
                        Text("VOICE MEMO")
                            .font(.dMono(size: 10, weight: .bold))
                            .foregroundStyle(Color.dSecondary)
                            .tracking(1)
                    }

                    Text(formatTime(sessionElapsed))
                        .font(.dMono(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.dText)

                    PulsingDot(size: 6)
                } else {
                    Text("ON-DEVICE")
                        .font(.dMono(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.dAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.dAmber.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.dSurface)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.dDim)
            Text("No active session")
                .font(.dMono(size: 13, weight: .bold))
                .foregroundStyle(Color.dSecondary)
            Text("Start a call capture or voice memo\nto begin transcribing.")
                .font(.dMono(size: 11, weight: .medium))
                .foregroundStyle(Color.dDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Save Banner

    private func saveBanner(url: URL) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.dGreen.opacity(0.15))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.dGreen)
                )
            Text("Saved to \(url.lastPathComponent)")
                .font(.dMono(size: 11, weight: .bold))
                .foregroundStyle(Color.dText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("SHOW") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                savedFileURL = nil
            }
            .font(.dMono(size: 10, weight: .bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.dAmber)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dSurface)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Helpers

    private var isRunning: Bool {
        transcriptionEngine?.isRunning ?? false
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Actions

    /// Start a client-specific recording. Captures frontmost app synchronously before async work.
    private func startClientRecording() {
        let client = clientRegistry.selectedClient
        activeClient = client
        savedFileURL = nil

        if let client {
            clientRegistry.recordUsage(for: client)
        }

        // Capture frontmost app synchronously before async Task
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let appName = bundleID.flatMap { conferencingBundleIDs[$0] }

        transcriptStore.clear()
        silenceSeconds = 0
        sessionElapsed = 0
        savedFileURL = nil

        let outputPath = settings.vaultMeetingsPath
        let sourceApp = appName ?? "Call"
        let preCallNotes = editableContext

        Task {
            transcriptionEngine?.lastError = nil
            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: sourceApp,
                    vaultPath: outputPath,
                    sessionType: .callCapture,
                    client: client,
                    attendees: genericAttendees.isEmpty ? nil : genericAttendees
                )
            } catch {
                await sessionStore.endSession()
                transcriptionEngine?.lastError = error.localizedDescription
                return
            }
            if !preCallNotes.isEmpty {
                await transcriptLogger.updateContext(preCallNotes)
            }
            activeSessionType = .callCapture
            detectedAppName = appName
            let corrector = buildVocabularyCorrector(client: client)
            await transcriptionEngine?.start(
                locale: settings.locale,
                inputDeviceID: settings.inputDeviceID,
                appBundleID: appName != nil ? bundleID : nil,
                preferBuiltInMic: settings.preferBuiltInMicDuringCalls,
                vocabularyCorrector: corrector
            )
        }
    }

    private func startSession(type: SessionType) {
        // If in side-by-side mode with a selected client, use client recording
        if clientRegistry.hasClients && clientRegistry.selectedClient != nil && type == .callCapture {
            startClientRecording()
            return
        }

        transcriptStore.clear()
        silenceSeconds = 0
        sessionElapsed = 0
        savedFileURL = nil
        activeClient = nil

        let outputPath: String
        let sourceApp: String
        var appBundleID: String?
        var resolvedAppName: String?

        var genericContextLabel: String?

        switch type {
        case .callCapture:
            outputPath = settings.vaultMeetingsPath
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier,
               let appName = conferencingBundleIDs[bundleID] {
                sourceApp = appName
                appBundleID = bundleID
                resolvedAppName = appName
            } else {
                sourceApp = "Call"
            }
            if !genericAttendees.isEmpty {
                genericContextLabel = genericAttendees
            }
        case .voiceMemo:
            outputPath = settings.vaultVoicePath
            sourceApp = "Voice Memo"
            editableContext = ""
        }

        let preCallNotes = editableContext

        Task {
            transcriptionEngine?.lastError = nil
            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: sourceApp,
                    vaultPath: outputPath,
                    sessionType: type,
                    context: genericContextLabel,
                    attendees: genericAttendees.isEmpty ? nil : genericAttendees
                )
            } catch {
                await sessionStore.endSession()
                transcriptionEngine?.lastError = error.localizedDescription
                return
            }
            if type == .callCapture && !preCallNotes.isEmpty {
                await transcriptLogger.updateContext(preCallNotes)
            }
            activeSessionType = type
            detectedAppName = resolvedAppName
            let corrector = buildVocabularyCorrector(client: nil)
            if type == .callCapture {
                await transcriptionEngine?.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID,
                    appBundleID: appBundleID,
                    preferBuiltInMic: settings.preferBuiltInMicDuringCalls,
                    vocabularyCorrector: corrector
                )
            } else {
                await transcriptionEngine?.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID,
                    micOnly: true,
                    vocabularyCorrector: corrector
                )
            }
        }
    }

    private func stopSession() {
        activeSessionType = nil
        detectedAppName = nil
        silenceSeconds = 0

        Task {
            savedFileURL = nil
            await transcriptionEngine?.stop()
            await sessionStore.endSession()
            contextUpdateTask?.cancel()
            if !editableContext.isEmpty {
                await transcriptLogger.updateContext(editableContext)
            }
            if !genericAttendees.isEmpty {
                await transcriptLogger.updateAttendees(genericAttendees)
            }
            await transcriptLogger.endSession()

            transcriptionEngine?.assetStatus = "Refining speakers..."
            await transcriptionEngine?.runOfflineDiarization()

            if settings.enablePostSessionRefinement {
                transcriptionEngine?.assetStatus = "Polishing transcript..."
                let corrections = await PostSessionRefiner.refine(
                    transcriptStore.utterances,
                    reusing: dictationController.pipeline.residentMLXRefiner
                )
                for correction in corrections {
                    transcriptStore.updateText(at: correction.index, text: correction.refined)
                }
            }

            let speakers = Set(transcriptStore.utterances.map(\.speakerName))
            await transcriptLogger.updateSpeakers(speakers)
            await transcriptLogger.rewriteTranscriptBody(from: transcriptStore.utterances)

            transcriptionEngine?.assetStatus = "Finalizing..."
            let savedPath = await transcriptLogger.finalizeFrontmatter()
            transcriptionEngine?.assetStatus = "Ready"

            transcriptStore.clear()

            if activeSessionType == nil, let savedPath {
                savedFileURL = savedPath
            }

            activeClient = nil
        }
    }

    private func buildVocabularyCorrector(client: ClientInfo?) -> VocabularyCorrector? {
        var vocabTerms: [String] = []
        var vocabCorrections: [String: String] = [:]

        if let client = client ?? clientRegistry.selectedClient {
            vocabTerms.append(contentsOf: client.allParticipantNames)
            vocabTerms.append(client.name)
        }

        if !genericAttendees.isEmpty {
            let names = genericAttendees.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            vocabTerms.append(contentsOf: names)
        }

        for pack in BundledVocabulary.allPacks where settings.enabledVocabPacks.contains(pack.id) {
            vocabTerms.append(contentsOf: pack.terms)
            vocabCorrections.merge(pack.corrections) { _, new in new }
        }

        if let vocabDir = settings.vocabularyURL {
            let vocabSet = VocabularyLoader.load(from: vocabDir)
            vocabTerms.append(contentsOf: vocabSet.terms)
            vocabCorrections.merge(vocabSet.corrections) { _, new in new }
        }

        guard !vocabTerms.isEmpty || !vocabCorrections.isEmpty else { return nil }
        return VocabularyCorrector(terms: vocabTerms, corrections: vocabCorrections)
    }

    private func handleNewUtterance() {
        guard let last = transcriptStore.utterances.last else { return }

        silenceSeconds = 0

        Task {
            await transcriptLogger.append(
                speaker: last.speakerName,
                text: last.text,
                timestamp: last.timestamp
            )
        }

        Task {
            await sessionStore.appendRecord(SessionRecord(
                speaker: last.speaker,
                timestamp: last.timestamp,
                speakerName: last.speakerName
            ))
        }
    }
}

struct ModelDownloadBanner: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.dAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Downloading model")
                    .font(.dMono(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dText)
                Text(progress > 0
                    ? "\(Int(progress * 100))% of ~1.8 GB"
                    : "Preparing download…")
                    .font(.dMono(size: 10, weight: .medium))
                    .foregroundStyle(Color.dDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dSurface)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
    }
}
