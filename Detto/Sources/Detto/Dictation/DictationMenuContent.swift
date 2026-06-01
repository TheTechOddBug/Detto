import SwiftUI

struct DictationMenuContent: View {
    let controller: DictationController

    private var state: DictationState { controller.state }

    private var statusText: String {
        switch state.recordingState {
        case .idle:
            return state.isModelLoaded ? "Ready" : "Model not loaded"
        case .loadingModel:
            let pct = Int(state.modelDownloadProgress * 100)
            return "Loading model... \(pct)%"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        }
    }

    var body: some View {
        Text(statusText)
            .font(.headline)

        Divider()

        Menu("Hotkey") {
            ForEach(HotkeyOption.allCases, id: \.self) { option in
                Button {
                    controller.updateHotkey(option)
                } label: {
                    HStack {
                        Text(option.keyName)
                        if option == HotkeyOption.saved {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Toggle("Toggle mode (double-press)", isOn: Binding(
                get: { HotkeyOption.isToggleMode },
                set: { controller.updateToggleMode($0) }
            ))
        }

        if !state.hasAccessibilityPermission {
            Button("Grant Accessibility Permission...") {
                HotkeyManager.requestAccessibilityPermission()
            }
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",")

        Button("Quit Detto") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
