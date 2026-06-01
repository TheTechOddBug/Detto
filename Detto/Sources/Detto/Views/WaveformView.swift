import SwiftUI

struct WaveformView: View {
    let isRecording: Bool
    let audioLevel: Float

    var body: some View {
        if isRecording {
            SpectrumVisualizer(audioLevel: audioLevel)
                .frame(height: 28)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.dRule)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .frame(height: 28)
        }
    }
}

private let barCount = 24

private let positionCurve: [Float] = (0..<barCount).map { i in
    let x = (Float(i) - Float(barCount - 1) / 2) / (Float(barCount) / 4)
    return exp(-x * x / 2)
}

private struct SpectrumVisualizer: View {
    let audioLevel: Float

    @State private var barOffsets: [Float] = []
    @State private var barHeights: [CGFloat] = Array(repeating: 0, count: barCount)
    @State private var peakHeights: [CGFloat] = Array(repeating: 0, count: barCount)
    @State private var peakTimers: [Int] = Array(repeating: 0, count: barCount)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.dAmber)
                        .frame(height: max(barHeights[i], peakHeights[i]))
                        .frame(maxHeight: 13, alignment: .bottom)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.dAmber.opacity(0.5))
                        .frame(height: max(barHeights[i], peakHeights[i]) * 0.8)
                        .frame(maxHeight: 13, alignment: .top)
                }
            }
        }
        .padding(.horizontal, 12)
        .drawingGroup()
        .onAppear {
            barOffsets = (0..<barCount).map { _ in Float.random(in: -0.15...0.15) }
        }
        .onChange(of: audioLevel) {
            updateBars()
        }
    }

    private func updateBars() {
        let level = CGFloat(audioLevel)

        for i in 0..<barCount {
            barOffsets[i] = Float.random(in: -0.15...0.15)
        }

        var newHeights = [CGFloat](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let curve = CGFloat(positionCurve[i])
            let jitter = CGFloat(1.0 + barOffsets[i])
            newHeights[i] = level * curve * jitter * 13
        }

        var newPeaks = peakHeights
        var newTimers = peakTimers
        for i in 0..<barCount {
            if newHeights[i] >= newPeaks[i] {
                newPeaks[i] = newHeights[i]
                newTimers[i] = 3
            } else if newTimers[i] > 0 {
                newTimers[i] -= 1
            } else {
                newPeaks[i] = newPeaks[i] * 0.7 + newHeights[i] * 0.3
                if newPeaks[i] < 0.5 { newPeaks[i] = 0 }
            }
        }

        peakTimers = newTimers

        withAnimation(.easeOut(duration: 0.12)) {
            barHeights = newHeights
        }
        withAnimation(.easeIn(duration: 0.4)) {
            peakHeights = newPeaks
        }
    }
}
