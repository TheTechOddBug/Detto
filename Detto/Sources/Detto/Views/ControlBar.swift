import SwiftUI

struct PulsingDot: View {
    var size: CGFloat = 10
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.dRed)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ControlBar: View {
    let isRecording: Bool
    let activeSessionType: SessionType?
    let audioLevel: Float
    let detectedApp: String?
    let silenceSeconds: Int
    let statusMessage: String?
    let errorMessage: String?
    var activeClientName: String? = nil
    let onStartCallCapture: () -> Void
    let onStartVoiceMemo: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(.dMono(size: 10, weight: .medium))
                    .foregroundStyle(Color.dRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if let status = statusMessage, status != "Ready" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.dAmber)
                    Text(status)
                        .font(.dMono(size: 11, weight: .medium))
                        .foregroundStyle(Color.dSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if isRecording {
                if silenceSeconds >= 90 {
                    Text("Silence - auto-stop in \(120 - silenceSeconds)s")
                        .font(.dMono(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }

                Button(action: onStop) {
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
                .keyboardShortcut(".", modifiers: .command)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    Button(action: onStartCallCapture) {
                        HStack(spacing: 4) {
                            Text("CALL CAPTURE")
                                .font(.dMono(size: 11, weight: .bold))
                                .foregroundStyle(Color.dText)
                                .fixedSize()
                            Spacer(minLength: 2)
                            Text("\u{2318}R")
                                .font(.dMono(size: 10, weight: .medium))
                                .foregroundStyle(Color.dDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(Color.dAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)

                    Button(action: onStartVoiceMemo) {
                        HStack(spacing: 4) {
                            Text("VOICE MEMO")
                                .font(.dMono(size: 11, weight: .bold))
                                .foregroundStyle(Color.dAmber)
                                .fixedSize()
                            Spacer(minLength: 2)
                            Text("\u{2318}\u{21E7}R")
                                .font(.dMono(size: 10, weight: .medium))
                                .foregroundStyle(Color.dAmber.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dAmber, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(Color.dSurface)
        .overlay(Divider(), alignment: .top)
    }
}
