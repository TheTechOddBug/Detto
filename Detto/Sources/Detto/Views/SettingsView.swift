import SwiftUI
import CoreAudio
import Sparkle

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var updater: SPUUpdater
    var dictationController: DictationController
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $settings.inputDeviceID) {
                    Text("System Default").tag(AudioDeviceID(0))
                    ForEach(inputDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .font(.dMono(size: 12, weight: .medium))
            } header: {
                sectionHeader("AUDIO")
            }

            DictationSettingsSection(controller: dictationController)

            Section {
                folderRow(
                    label: "Vault Root",
                    detail: "Client quick-select source",
                    path: settings.vaultRootPath,
                    emptyText: "Not configured"
                ) { url in
                    settings.vaultRootPath = url.path
                    settings.vaultRootBookmark = settings.createBookmark(for: url)
                }

                folderRow(
                    label: "Meetings",
                    detail: "Call capture transcripts",
                    path: settings.vaultMeetingsPath,
                    emptyText: "No folder selected"
                ) { url in
                    settings.vaultMeetingsPath = url.path
                    settings.vaultMeetingsBookmark = settings.createBookmark(for: url)
                }

                folderRow(
                    label: "Voice Memos",
                    detail: "Voice memo transcripts",
                    path: settings.vaultVoicePath,
                    emptyText: "No folder selected"
                ) { url in
                    settings.vaultVoicePath = url.path
                    settings.vaultVoiceBookmark = settings.createBookmark(for: url)
                }
            } header: {
                sectionHeader("STORAGE")
            }

            Section {
                folderRow(
                    label: "Custom Vocabulary",
                    detail: "Custom vocabulary files",
                    path: settings.vocabularyPath,
                    emptyText: "Not configured"
                ) { url in
                    settings.vocabularyPath = url.path
                    settings.vocabularyBookmark = settings.createBookmark(for: url)
                }

                if !settings.vocabularyPath.isEmpty {
                    Button(action: {
                        settings.vocabularyPath = ""
                        settings.vocabularyBookmark = nil
                    }) {
                        HStack {
                            Text("Clear custom vocabulary folder")
                                .font(.dMono(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(BundledVocabulary.allPacks, id: \.id) { pack in
                    Toggle(isOn: Binding(
                        get: { settings.enabledVocabPacks.contains(pack.id) },
                        set: { enabled in
                            if enabled {
                                settings.enabledVocabPacks.insert(pack.id)
                            } else {
                                settings.enabledVocabPacks.remove(pack.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.displayName)
                                .font(.dMono(size: 12, weight: .medium))
                            Text("~\(pack.termCount) terms")
                                .font(.dMono(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                sectionHeader("VOCABULARY")
            }

            Section {
                Toggle("Polish transcript after recording", isOn: $settings.enablePostSessionRefinement)
                    .font(.dMono(size: 12, weight: .medium))
                Text("Uses on-device AI to fix proper nouns and grammar in the final transcript.")
                    .font(.dMono(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("REFINEMENT")
            }

            Section {
                Toggle("Hide from screen sharing", isOn: $settings.hideFromScreenShare)
                    .font(.dMono(size: 12, weight: .medium))
                Text("When enabled, the app is invisible during screen sharing and recording.")
                    .font(.dMono(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("PRIVACY")
            }

            Section {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .font(.dMono(size: 12, weight: .medium))
            } header: {
                sectionHeader("ABOUT")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 700)
        .tint(Color.dAmber)
        .onAppear {
            inputDevices = MicCapture.availableInputDevices()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.dMono(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(Color.dDim)
    }

    private func folderRow(
        label: String, detail: String, path: String,
        emptyText: String, onSelect: @escaping (URL) -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dMono(size: 12, weight: .semibold))
                Text(path.isEmpty ? emptyText : path)
                    .font(.dMono(size: 11, weight: .medium))
                    .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Choose...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Choose folder for \(detail.lowercased())"
                if panel.runModal() == .OK, let url = panel.url {
                    onSelect(url)
                }
            }
            .font(.dMono(size: 11, weight: .semibold))
        }
    }
}
