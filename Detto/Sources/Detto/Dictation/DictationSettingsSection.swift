import SwiftUI

struct DictationSettingsSection: View {
    let controller: DictationController

    private var state: DictationState { controller.state }

    @State private var selectedHotkey: HotkeyOption = HotkeyOption.saved
    @State private var isToggleMode: Bool = HotkeyOption.isToggleMode

    var body: some View {
        Section {
            Picker("Hotkey", selection: $selectedHotkey) {
                ForEach(HotkeyOption.allCases, id: \.self) { option in
                    Text(option.keyName).tag(option)
                }
            }
            .font(.dMono(size: 12, weight: .medium))
            .onChange(of: selectedHotkey) { _, newValue in
                controller.updateHotkey(newValue)
            }

            Toggle("Toggle mode (double-press to start/stop)", isOn: $isToggleMode)
                .font(.dMono(size: 12, weight: .medium))
                .onChange(of: isToggleMode) { _, newValue in
                    controller.updateToggleMode(newValue)
                }

            HStack {
                Text("Accessibility")
                    .font(.dMono(size: 12, weight: .medium))
                Spacer()
                if state.hasAccessibilityPermission {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.dMono(size: 11, weight: .medium))
                        .foregroundStyle(Color.dGreen)
                } else {
                    Button("Grant Permission...") {
                        HotkeyManager.requestAccessibilityPermission()
                    }
                    .font(.dMono(size: 11, weight: .semibold))
                }
            }
        } header: {
            Text("DICTATION")
                .font(.dMono(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.dDim)
        }
    }
}
