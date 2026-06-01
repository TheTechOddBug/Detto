import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var micGranted = false
    @State private var screenGranted = false
    @State private var accessibilityGranted = false

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: modelDownloadStep
                default: readyStep
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color.dAmber : Color.dRule)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 20)

            HStack {
                Button("SKIP") {
                    finish()
                }
                .buttonStyle(.plain)
                .font(.dMono(size: 10, weight: .bold))
                .foregroundStyle(Color.dDim)

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStep += 1
                        }
                    } label: {
                        Text(currentStep == 0 ? "GET STARTED" : "CONTINUE")
                            .font(.dMono(size: 12, weight: .bold))
                            .foregroundStyle(Color.dText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.dAmber, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        finish()
                    } label: {
                        Text("OPEN DETTO")
                            .font(.dMono(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.dGreen, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dBg)
        .task {
            refreshPermissionState()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.dAmber)
                .frame(height: 52)

            Spacer().frame(height: 10)

            DettoWordmark(size: 24)

            Text("Local meeting transcription, client briefing, and system-wide dictation. All on-device. No API keys, no cloud.")
                .font(.dMono(size: 12, weight: .medium))
                .foregroundStyle(Color.dSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.dAmber)
                .frame(height: 52)

            Spacer().frame(height: 4)

            Text("PERMISSIONS")
                .font(.dMono(size: 14, weight: .black))
                .tracking(2)

            Text("Detto needs a few permissions to work. Grant them now so everything is ready.")
                .font(.dMono(size: 12, weight: .medium))
                .foregroundStyle(Color.dSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                permissionRow(
                    icon: "mic.fill",
                    label: "Microphone",
                    detail: "Captures your voice",
                    granted: micGranted,
                    action: requestMicrophone
                )

                permissionRow(
                    icon: "rectangle.on.rectangle",
                    label: "Screen Recording",
                    detail: "System audio from conferencing apps",
                    granted: screenGranted,
                    action: requestScreenRecording
                )

                permissionRow(
                    icon: "accessibility",
                    label: "Accessibility",
                    detail: "Injects dictated text at your cursor",
                    granted: accessibilityGranted,
                    action: requestAccessibility
                )
            }
            .padding(.top, 4)
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.dAmber)
                .frame(height: 52)

            Spacer().frame(height: 4)

            Text("MODELS")
                .font(.dMono(size: 14, weight: .black))
                .tracking(2)

            Text("Detto downloads speech and language models on first launch. This happens in the background.")
                .font(.dMono(size: 12, weight: .medium))
                .foregroundStyle(Color.dSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                modelRow(name: "Parakeet v3", detail: "Speech recognition (ANE)")
                modelRow(name: "Llama 3.2 3B", detail: "Text refinement (GPU)")
            }
            .padding(.top, 4)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.dGreen)
                .frame(height: 52)

            Spacer().frame(height: 10)

            Text("READY")
                .font(.dMono(size: 14, weight: .black))
                .tracking(2)

            Text("Start a call capture or voice memo from the main window. Hold your dictation hotkey anywhere to transcribe on the fly.")
                .font(.dMono(size: 12, weight: .medium))
                .foregroundStyle(Color.dSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Permission Row

    private func permissionRow(icon: String, label: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.dAmber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dMono(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dText)
                Text(detail)
                    .font(.dMono(size: 11, weight: .medium))
                    .foregroundStyle(Color.dDim)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.dGreen)
            } else {
                Button("GRANT") {
                    action()
                }
                .font(.dMono(size: 10, weight: .bold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.dText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.dAmber, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dText, lineWidth: 2.5))
    }

    private func modelRow(name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.dAmber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.dMono(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dText)
                Text(detail)
                    .font(.dMono(size: 11, weight: .medium))
                    .foregroundStyle(Color.dDim)
            }

            Spacer()

            Text("AUTO")
                .font(.dMono(size: 9, weight: .bold))
                .foregroundStyle(Color.dAmber)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.dAmber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dRule, lineWidth: 1.5))
    }

    // MARK: - Permission Actions

    private func requestMicrophone() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { micGranted = granted }
        }
    }

    private func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let granted = CGPreflightScreenCaptureAccess()
                await MainActor.run { screenGranted = granted }
                if granted { break }
            }
        }
    }

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityGranted = trusted
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let isTrusted = AXIsProcessTrusted()
                await MainActor.run { accessibilityGranted = isTrusted }
                if isTrusted { break }
            }
        }
    }

    private func refreshPermissionState() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
