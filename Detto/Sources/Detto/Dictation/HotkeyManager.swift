import AppKit
import Carbon.HIToolbox

final class HotkeyManager: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyActive = false
    private var hotkeyOption: HotkeyOption
    private var isToggleMode: Bool

    private var activeCombo: CustomHotkeyCombo?

    private let kVK_RightOption: Int64 = 0x3D
    private let kVK_RightCommand: Int64 = 0x36
    private let kVK_Space: Int64 = 0x31

    private let doublePressWindow: TimeInterval = 0.4
    private var lastPressReleaseTime: TimeInterval?
    private var isKeyCurrentlyHeld: Bool = false
    private var doublePressResetTimer: Timer?
    private var isToggleRecording: Bool = false

    private var isSuspended = false
    private var lastReleaseTime: TimeInterval = 0

    var isRunning: Bool { eventTap != nil }

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onToggle: ((Bool) -> Void)?

    init(hotkeyOption: HotkeyOption = HotkeyOption.saved) {
        self.hotkeyOption = hotkeyOption
        self.isToggleMode = HotkeyOption.isToggleMode
        if hotkeyOption == .custom {
            self.activeCombo = HotkeyOption.activeCustomCombo
        }
    }

    func start() -> Bool {
        guard !isRunning else { return true }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return false
        }

        var eventMask = (1 << CGEventType.flagsChanged.rawValue)

        if hotkeyOption == .ctrlOptionSpace {
            eventMask |= (1 << CGEventType.keyDown.rawValue)
            eventMask |= (1 << CGEventType.keyUp.rawValue)
        }

        if hotkeyOption == .custom, let combo = activeCombo, !combo.triggerIsModifier {
            eventMask |= (1 << CGEventType.keyDown.rawValue)
            eventMask |= (1 << CGEventType.keyUp.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if isSuspended {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        var hotkeyPressed = false

        switch hotkeyOption {
        case .fnKey:
            if type == .flagsChanged {
                hotkeyPressed = flags.contains(.maskSecondaryFn)
            }

        case .control:
            let kVK_LeftControl: Int64 = 0x3B
            if type == .flagsChanged {
                hotkeyPressed = flags.contains(.maskControl) && keyCode == kVK_LeftControl
                if !hotkeyPressed && isHotkeyActive && flags.contains(.maskControl) {
                    hotkeyPressed = true
                }
            }

        case .rightOption:
            if type == .flagsChanged {
                hotkeyPressed = flags.contains(.maskAlternate) && keyCode == kVK_RightOption
                if !hotkeyPressed && isHotkeyActive && flags.contains(.maskAlternate) {
                    hotkeyPressed = true
                }
            }

        case .rightCommand:
            if type == .flagsChanged {
                hotkeyPressed = flags.contains(.maskCommand) && keyCode == kVK_RightCommand
                if !hotkeyPressed && isHotkeyActive && flags.contains(.maskCommand) {
                    hotkeyPressed = true
                }
            }

        case .hyperKey:
            if type == .flagsChanged {
                let hyperFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
                hotkeyPressed = flags.contains(hyperFlags)
            }

        case .ctrlOptionSpace:
            let hasCtrlOption = flags.contains(.maskControl) && flags.contains(.maskAlternate)

            if type == .keyDown && keyCode == kVK_Space && hasCtrlOption {
                hotkeyPressed = true
            } else if type == .keyUp && keyCode == kVK_Space && isHotkeyActive {
                hotkeyPressed = false
            } else if isHotkeyActive && hasCtrlOption {
                hotkeyPressed = true
            }

        case .custom:
            guard let combo = activeCombo else { break }

            if combo.triggerIsModifier {
                if type == .flagsChanged {
                    let flagSet = modifierFlagIsSet(for: combo.triggerKeycode, flags: flags)
                    if keyCode == combo.triggerKeycode {
                        hotkeyPressed = flagSet
                    } else if isHotkeyActive && flagSet {
                        hotkeyPressed = true
                    }
                }
            } else {
                let requiredFlags = CGEventFlags(rawValue: combo.requiredModifierFlags)
                let hasRequiredModifiers = combo.requiredModifierFlags == 0 || flags.contains(requiredFlags)

                if type == .keyDown && keyCode == combo.triggerKeycode && hasRequiredModifiers {
                    hotkeyPressed = true
                } else if type == .keyUp && keyCode == combo.triggerKeycode {
                    hotkeyPressed = false
                } else if isHotkeyActive && type != .keyUp {
                    hotkeyPressed = true
                }
            }
        }

        if isToggleMode {
            if hotkeyPressed && !isKeyCurrentlyHeld {
                isKeyCurrentlyHeld = true
            } else if !hotkeyPressed && isKeyCurrentlyHeld {
                isKeyCurrentlyHeld = false
                handleKeyRelease()
            }
            return Unmanaged.passRetained(event)
        }

        if hotkeyPressed && !isHotkeyActive {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastReleaseTime > 0.3 else {
                return Unmanaged.passRetained(event)
            }
            isHotkeyActive = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !hotkeyPressed && isHotkeyActive {
            isHotkeyActive = false
            lastReleaseTime = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }

        return Unmanaged.passRetained(event)
    }

    func resetToggleState() {
        isToggleRecording = false
    }

    private func handleKeyRelease() {
        let now = ProcessInfo.processInfo.systemUptime

        doublePressResetTimer?.invalidate()
        doublePressResetTimer = nil

        if let lastTap = lastPressReleaseTime, now - lastTap < doublePressWindow {
            isToggleRecording.toggle()
            lastPressReleaseTime = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onToggle?(self.isToggleRecording)
            }
        } else {
            lastPressReleaseTime = now
            doublePressResetTimer = Timer.scheduledTimer(withTimeInterval: doublePressWindow, repeats: false) { [weak self] _ in
                self?.lastPressReleaseTime = nil
            }
        }
    }

    func suspend() {
        isSuspended = true
    }

    func resume() {
        isSuspended = false
    }

    func modifierFlagIsSet(for keycode: Int64, flags: CGEventFlags) -> Bool {
        switch keycode {
        case 0x37, 0x36: return flags.contains(.maskCommand)
        case 0x3A, 0x3D: return flags.contains(.maskAlternate)
        case 0x38, 0x3C: return flags.contains(.maskShift)
        case 0x3B, 0x3E: return flags.contains(.maskControl)
        case 0x3F:       return flags.contains(.maskSecondaryFn)
        default:         return false
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHotkeyActive = false
        isSuspended = false

        doublePressResetTimer?.invalidate()
        doublePressResetTimer = nil
        lastPressReleaseTime = nil
        isKeyCurrentlyHeld = false
        isToggleRecording = false
    }

    func updateHotkey(_ option: HotkeyOption) {
        stop()
        hotkeyOption = option
        HotkeyOption.saved = option
        if option == .custom {
            activeCombo = HotkeyOption.activeCustomCombo
        } else {
            activeCombo = nil
        }
        _ = start()
    }

    func updateToggleMode(_ isToggle: Bool) {
        stop()
        isToggleMode = isToggle
        _ = start()
    }

    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
