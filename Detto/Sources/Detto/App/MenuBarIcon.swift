import SwiftUI

@Observable @MainActor
final class MenuBarAnimator {
    private let state: DictationState
    private var timer: Timer?
    var wavePhase: Double = 0
    var spinnerAngle: Double = 0

    init(state: DictationState) {
        self.state = state
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        switch state.recordingState {
        case .recording:
            wavePhase += 0.08
        case .transcribing:
            spinnerAngle += 12
        default:
            break
        }
    }
}

struct MenuBarLabel: View {
    let state: DictationState
    let animator: MenuBarAnimator

    var body: some View {
        switch state.recordingState {
        case .idle:
            Text("D")
                .font(.custom("Azeret Mono", size: 14).weight(.black))
                .opacity(state.isModelLoaded ? 1.0 : 0.4)
        case .recording:
            HStack(spacing: 1.5) {
                waveBar(offset: 0)
                waveBar(offset: 0.6)
                Text("D")
                    .font(.custom("Azeret Mono", size: 14).weight(.black))
                waveBar(offset: 0.3)
                waveBar(offset: 0.9)
            }
            .foregroundStyle(Color.dAmber)
        case .transcribing:
            ZStack {
                Text("D")
                    .font(.custom("Azeret Mono", size: 14).weight(.black))
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(animator.spinnerAngle))
            }
            .foregroundStyle(Color.dAmber)
        case .loadingModel:
            ZStack {
                Text("D")
                    .font(.custom("Azeret Mono", size: 14).weight(.black))
                Circle()
                    .stroke(lineWidth: 1.5)
                    .opacity(0.2)
                    .frame(width: 16, height: 16)
                Circle()
                    .trim(from: 0, to: state.modelDownloadProgress)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
            }
            .foregroundStyle(Color.dDim)
        }
    }

    private func waveBar(offset: Double) -> some View {
        let level = CGFloat(min(max(state.audioLevel, 0.15), 1.0))
        let wave = sin((animator.wavePhase + offset) * .pi * 2) * 0.5 + 0.5
        let h = 2 + 6 * level * wave
        return RoundedRectangle(cornerRadius: 0.75)
            .frame(width: 1.5, height: h)
    }
}
