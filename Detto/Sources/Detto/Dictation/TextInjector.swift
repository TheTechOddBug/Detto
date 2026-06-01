import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class TextInjector {

    // MARK: - Types

    private enum OriginalClipboard {
        case empty
        case items([NSPasteboardItem])
        case unrecoverable
    }

    private struct ClipboardSession {
        let original: OriginalClipboard
        let id: UUID
        let injectedChangeCount: Int
        let injectedText: String
    }

    private struct TextStateSnapshot: Equatable {
        let selectedTextRange: NSRange?
        let numberOfCharacters: Int?

        var hasSignal: Bool {
            selectedTextRange != nil || numberOfCharacters != nil
        }
    }

    private enum PasteDetectionResult {
        case detected
        case clipboardChanged
        case timeout
        case noSignalAvailable
    }

    // MARK: - Configuration

    private let accessibilityTimeout: Duration = .seconds(1)
    private let fallbackDelay: Duration = .milliseconds(50)

    // MARK: - State

    private var session: ClipboardSession?
    private var restoreTask: Task<Void, Never>?

    // MARK: - Public API

    func inject(text: String) async {
        let pasteboard = NSPasteboard.general

        let original: OriginalClipboard
        if let existingSession = session, pasteboard.changeCount == existingSession.injectedChangeCount {
            original = existingSession.original
        } else {
            session = nil
            original = snapshotOriginalClipboard(from: pasteboard)
        }

        restoreTask?.cancel()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let injectedChangeCount = pasteboard.changeCount

        let sessionId = UUID()
        session = ClipboardSession(
            original: original,
            id: sessionId,
            injectedChangeCount: injectedChangeCount,
            injectedText: text
        )

        let focusedElement = fetchFocusedUIElement()
        let baseline = focusedElement.map { snapshotTextState(of: $0) }

        simulatePaste()

        restoreTask = Task { @MainActor in
            let result = await self.waitForPasteCompletion(
                pasteboard: pasteboard,
                sessionId: sessionId,
                focusedElement: focusedElement,
                baseline: baseline
            )

            if case .clipboardChanged = result {
                self.session = nil
                return
            }

            self.restoreClipboard(on: pasteboard, sessionId: sessionId)
        }
    }

    // MARK: - Paste Detection

    private func waitForPasteCompletion(
        pasteboard: NSPasteboard,
        sessionId: UUID,
        focusedElement: AXUIElement?,
        baseline: TextStateSnapshot?
    ) async -> PasteDetectionResult {

        guard let currentSession = session, currentSession.id == sessionId else {
            return .clipboardChanged
        }
        if pasteboard.changeCount != currentSession.injectedChangeCount {
            return .clipboardChanged
        }

        if let element = focusedElement,
           AccessibilityObserver.supportsTextChangeNotifications(element: element) {
            let observer = AccessibilityObserver()
            do {
                try await observer.waitForTextChange(on: element, timeout: accessibilityTimeout)
                return .detected
            } catch AccessibilityObserver.ObserverError.timeout {
                // Fall through to polling
            } catch {
                // Fall through to polling/fallback
            }
        }

        if let element = focusedElement, let baseline = baseline, baseline.hasSignal {
            let pollResult = await pollForTextChange(
                element: element,
                baseline: baseline,
                pasteboard: pasteboard,
                sessionId: sessionId
            )
            if pollResult != .noSignalAvailable {
                return pollResult
            }
        }

        try? await Task.sleep(for: fallbackDelay)

        guard let currentSession = session, currentSession.id == sessionId else {
            return .clipboardChanged
        }
        if pasteboard.changeCount != currentSession.injectedChangeCount {
            return .clipboardChanged
        }

        return .noSignalAvailable
    }

    private func pollForTextChange(
        element: AXUIElement,
        baseline: TextStateSnapshot,
        pasteboard: NSPasteboard,
        sessionId: UUID
    ) async -> PasteDetectionResult {
        let pollInterval: Duration = .milliseconds(50)
        let maxPolls = 20

        for _ in 0..<maxPolls {
            guard let currentSession = session, currentSession.id == sessionId else {
                return .clipboardChanged
            }
            if pasteboard.changeCount != currentSession.injectedChangeCount {
                return .clipboardChanged
            }

            let current = snapshotTextState(of: element)
            if current.hasSignal && indicatesPasteConsumed(baseline: baseline, current: current) {
                return .detected
            }

            try? await Task.sleep(for: pollInterval)
        }

        return .timeout
    }

    // MARK: - Clipboard Operations

    private func snapshotOriginalClipboard(from pasteboard: NSPasteboard) -> OriginalClipboard {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return .empty }

        let snapshots: [NSPasteboardItem] = items.compactMap { item in
            let snapshot = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    snapshot.setString(string, forType: type)
                } else if let propertyList = item.propertyList(forType: type) {
                    snapshot.setPropertyList(propertyList, forType: type)
                }
            }
            return snapshot.types.isEmpty ? nil : snapshot
        }

        if !snapshots.isEmpty {
            return .items(snapshots)
        }

        return .unrecoverable
    }

    private func restoreClipboard(on pasteboard: NSPasteboard, sessionId: UUID) {
        guard let currentSession = session, currentSession.id == sessionId else { return }
        guard pasteboard.changeCount == currentSession.injectedChangeCount else {
            session = nil
            return
        }

        switch currentSession.original {
        case .unrecoverable:
            break
        case .empty:
            pasteboard.clearContents()
        case .items(let items):
            pasteboard.clearContents()
            let didWrite = pasteboard.writeObjects(items)
            if !didWrite {
                pasteboard.clearContents()
                pasteboard.setString(currentSession.injectedText, forType: .string)
            }
        }
        session = nil
    }

    // MARK: - Accessibility Helpers

    private func fetchFocusedUIElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard error == .success, let focused else { return nil }
        return (focused as! AXUIElement)
    }

    private func snapshotTextState(of element: AXUIElement) -> TextStateSnapshot {
        TextStateSnapshot(
            selectedTextRange: copyRangeAttribute(of: element, attribute: kAXSelectedTextRangeAttribute),
            numberOfCharacters: copyIntAttribute(of: element, attribute: kAXNumberOfCharactersAttribute)
        )
    }

    private func indicatesPasteConsumed(baseline: TextStateSnapshot, current: TextStateSnapshot) -> Bool {
        if let baselineRange = baseline.selectedTextRange, let currentRange = current.selectedTextRange {
            if baselineRange != currentRange { return true }
        }

        if let baselineCount = baseline.numberOfCharacters, let currentCount = current.numberOfCharacters {
            if baselineCount != currentCount { return true }
        }

        return false
    }

    private func copyIntAttribute(of element: AXUIElement, attribute: String) -> Int? {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard error == .success, let rawValue else { return nil }
        if let numberValue = rawValue as? NSNumber {
            return numberValue.intValue
        }
        return rawValue as? Int
    }

    private func copyRangeAttribute(of element: AXUIElement, attribute: String) -> NSRange? {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard error == .success, let rawValue else { return nil }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let axValue = (rawValue as! AXValue)

        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Keyboard Simulation

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 9

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
