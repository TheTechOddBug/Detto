import SwiftUI

struct TranscriptView: View {
    let utterances: [Utterance]
    let volatileYouText: String
    let volatileThemText: String

    var body: some View {
        GeometryReader { geo in
            let bubbleMax = max(200, geo.size.width * 0.72)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(utterances) { utterance in
                            UtteranceBubble(utterance: utterance, maxBubbleWidth: bubbleMax)
                                .id(utterance.id)
                        }

                        if !volatileYouText.isEmpty {
                            VolatileIndicator(text: volatileYouText, speaker: .you, maxBubbleWidth: bubbleMax)
                                .id("volatile-you")
                        }

                        if !volatileThemText.isEmpty {
                            VolatileIndicator(text: volatileThemText, speaker: .them, maxBubbleWidth: bubbleMax)
                                .id("volatile-them")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            .onChange(of: utterances.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = utterances.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: volatileYouText) {
                proxy.scrollTo("volatile-you", anchor: .bottom)
            }
            .onChange(of: volatileThemText) {
                proxy.scrollTo("volatile-them", anchor: .bottom)
            }
            }
        }
    }
}

// MARK: - Chat Bubble

private struct UtteranceBubble: View {
    let utterance: Utterance
    var maxBubbleWidth: CGFloat = 280

    private static let themColors: [Color] = [.dGreen, .dTeal, .dBlue]

    private var accentColor: Color {
        if utterance.speaker == .you { return .dAmber }
        let index = abs(utterance.speakerName.hashValue) % Self.themColors.count
        return Self.themColors[index]
    }

    var body: some View {
        HStack {
            if utterance.speaker == .you { Spacer() }

            VStack(alignment: .leading, spacing: 4) {
                Text(utterance.speakerName)
                    .font(.dMono(size: 10, weight: .black))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(accentColor)

                Text(utterance.text)
                    .font(.dBody(size: 13, weight: .medium))
                    .foregroundStyle(Color.dText)
                    .textSelection(.enabled)

                Text(utterance.timestamp, format: .dateTime.hour().minute())
                    .font(.dMono(size: 10, weight: .medium))
                    .foregroundStyle(Color.dDim)
            }
            .padding(10)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            .background(utterance.speaker == .you ? Color.dBubble : Color.dSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dText, lineWidth: 2.5))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(accentColor)
                    .frame(width: 4)
            }

            if utterance.speaker == .them { Spacer() }
        }
    }
}

// MARK: - Volatile Indicator

private struct VolatileIndicator: View {
    let text: String
    let speaker: Speaker
    var maxBubbleWidth: CGFloat = 280
    @State private var pulse = false

    private var accentColor: Color {
        speaker == .you ? .dAmber : .dGreen
    }

    var body: some View {
        HStack {
            if speaker == .you { Spacer() }

            HStack(spacing: 4) {
                Text(text)
                    .font(.dBody(size: 13, weight: .medium))
                    .foregroundStyle(Color.dDim)
                Circle()
                    .fill(Color.dAmber)
                    .frame(width: 4, height: 4)
            }
            .padding(10)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            .background(Color.dSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dRule, lineWidth: 1.5))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(accentColor)
                    .frame(width: 4)
            }
            .opacity(pulse ? 0.8 : 0.5)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            if speaker == .them { Spacer() }
        }
    }
}
