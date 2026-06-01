import AppKit
import SwiftUI

// MARK: - Pill Color Aliases

extension Color {
    static let ink = Color.dTitlebar
    static let dettoAmber = Color.dAmber
    static let dettoGreen = Color.dGreen
    static let dettoRed = Color.dRed
    static let dettoGray = Color.dDim
    static let dettoSurface = Color.dSurface
    static let dettoRule = Color.dRule
    static let darkBorder = Color(red: 0.15, green: 0.15, blue: 0.15)
}

// MARK: - Pill State

private enum PillState {
    case idle
    case listening
    case redline
    case processing
    case done
}

// MARK: - Panel Controller

@MainActor
class LiveTranscriptionPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPillView>?
    private var doneTimer: Timer?
    private let state: DictationState

    init(state: DictationState) {
        self.state = state
    }

    func show() {
        if panel != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 38),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: FloatingPillView(state: state))
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        self.hostingView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let fittingSize = hostingView.fittingSize
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.minY + 40
            panel.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true)
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func showDone() {
        doneTimer?.invalidate()
        doneTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        doneTimer?.invalidate()
        doneTimer = nil
        hostingView = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Floating Pill View

struct FloatingPillView: View {
    let state: DictationState

    private var pillState: PillState {
        switch state.recordingState {
        case .recording:
            return state.recordingDuration > 45 ? .redline : .listening
        case .transcribing:
            return .processing
        case .idle:
            return state.lastDictationJustFinished ? .done : .idle
        case .loadingModel:
            return .idle
        }
    }

    private var borderColor: Color {
        switch pillState {
        case .idle:       return Color.white.opacity(0.06)
        case .listening:  return Color(red: 0.45, green: 0.70, blue: 0.18).opacity(0.3)
        case .redline:    return Color.dettoRed.opacity(0.4)
        case .processing: return Color(white: 0.3).opacity(0.2)
        case .done:       return Color.dettoGreen.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if pillState == .processing {
                SpinnerView()
                    .frame(width: 10, height: 10)
                    .padding(.trailing, 4)
            }

            PillBarsView(state: state, pillState: pillState)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 11)
        .background(
            PillBackground()
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: pillState)
    }
}

// MARK: - Pill Background (frosted glass)

private struct PillBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Pill Bars (Winamp-style)

private struct PillBarsView: View {
    let state: DictationState
    let pillState: PillState

    private let barsPerSide = 5
    private let maxHeight: CGFloat = 13
    private let minHeight: CGFloat = 2
    private let barWidth: CGFloat = 1.8
    private let barSpacing: CGFloat = 1.3
    private let dotSize: CGFloat = 5

    @State private var barHeights: [CGFloat] = Array(repeating: 2, count: 5)

    private static let winampYellow = Color(red: 0.85, green: 0.82, blue: 0.15)
    private static let winampGreen  = Color(red: 0.10, green: 0.75, blue: 0.20)

    private func barColor(index: Int) -> Color {
        guard pillState == .listening || pillState == .redline else {
            switch pillState {
            case .done:       return .dettoGreen
            case .processing: return Color(white: 0.27)
            default:          return Color(white: 0.2)
            }
        }
        if pillState == .redline {
            let t = Double(index) / Double(max(barsPerSide - 1, 1))
            return Color(
                red: 0.85 - t * 0.35,
                green: 0.25 + t * 0.15,
                blue: 0.10
            )
        }
        let t = Double(index) / Double(max(barsPerSide - 1, 1))
        return Color(
            red:   0.85 + (0.10 - 0.85) * t,
            green: 0.82 + (0.75 - 0.82) * t,
            blue:  0.15 + (0.20 - 0.15) * t
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: pillState == .redline ? 0.06 : 0.1)) { timeline in
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach((0..<barsPerSide).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(index: i))
                        .frame(width: barWidth, height: barHeights[i])
                }

                Circle()
                    .fill(Color.dettoRed)
                    .frame(width: dotSize, height: dotSize)

                ForEach(0..<barsPerSide, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(index: i))
                        .frame(width: barWidth, height: barHeights[i])
                }
            }
            .frame(height: maxHeight)
            .onChange(of: timeline.date) { _, _ in
                updateBars()
            }
        }
        .animation(.easeInOut(duration: pillState == .redline ? 0.08 : 0.12), value: barHeights)
        .onChange(of: pillState) { _, newState in
            if newState == .done {
                withAnimation(.easeInOut(duration: 0.3)) {
                    barHeights = [4, 6, 8, 7, 5]
                }
            } else if newState == .idle || newState == .processing {
                withAnimation(.easeInOut(duration: 0.2)) {
                    barHeights = Array(repeating: minHeight, count: barsPerSide)
                }
            }
        }
    }

    private func updateBars() {
        guard pillState == .listening || pillState == .redline else { return }

        let raw = Double(state.audioLevel)
        let level = min(raw * 16.0, 1.0)
        let effectiveLevel = level > 0.01 ? level : Double.random(in: 0.15...0.45)

        for i in 0..<barsPerSide {
            let randomFactor = Double.random(in: 0.35...1.0)
            let target = minHeight + CGFloat(effectiveLevel * randomFactor) * (maxHeight - minHeight)
            barHeights[i] = max(minHeight, target)
        }
    }
}

// MARK: - Spinner

private struct SpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .stroke(Color.darkBorder, lineWidth: 2)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.dettoAmber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
            )
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
