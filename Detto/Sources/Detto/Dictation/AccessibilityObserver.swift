import ApplicationServices
import Foundation

final class AccessibilityObserver: @unchecked Sendable {

    enum ObserverError: Error {
        case failedToCreateObserver
        case failedToAddNotification
        case elementNotObservable
        case timeout
        case cancelled
    }

    static let textChangeNotifications: [String] = [
        kAXValueChangedNotification as String,
        kAXSelectedTextChangedNotification as String
    ]

    private var observer: AXObserver?
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    deinit {
        cleanup()
    }

    func waitForTextChange(
        on element: AXUIElement,
        timeout: Duration
    ) async throws {
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        guard pidResult == .success else {
            throw ObserverError.elementNotObservable
        }

        var observerRef: AXObserver?
        let callbackContext = Unmanaged.passUnretained(self).toOpaque()

        let createResult = AXObserverCreate(
            pid,
            accessibilityCallback,
            &observerRef
        )

        guard createResult == .success, let observer = observerRef else {
            throw ObserverError.failedToCreateObserver
        }

        self.observer = observer

        var addedAny = false
        for notification in Self.textChangeNotifications {
            let addResult = AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                callbackContext
            )
            if addResult == .success {
                addedAny = true
            }
        }

        guard addedAny else {
            cleanup()
            throw ObserverError.failedToAddNotification
        }

        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = cont
                lock.unlock()

                Task {
                    try await Task.sleep(for: timeout)
                    self.timeoutReached()
                }
            }
        } catch {
            cleanup()
            throw error
        }

        cleanup()
    }

    static func supportsTextChangeNotifications(element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else {
            return false
        }

        let observableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]

        return observableRoles.contains(role)
    }

    // MARK: - Private

    fileprivate func notificationReceived() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()

        cont?.resume(returning: ())
    }

    private func timeoutReached() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()

        cont?.resume(throwing: ObserverError.timeout)
    }

    private func cleanup() {
        lock.lock()
        if let observer = observer {
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.observer = nil
        }
        lock.unlock()
    }
}

private func accessibilityCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let observer = Unmanaged<AccessibilityObserver>.fromOpaque(refcon).takeUnretainedValue()
    observer.notificationReceived()
}
