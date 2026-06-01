import Foundation

struct CustomHotkeyCombo: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let triggerKeycode: Int64
    let triggerIsModifier: Bool
    let requiredModifierFlags: UInt64
    let displayName: String

    init(id: UUID = UUID(), triggerKeycode: Int64, triggerIsModifier: Bool, requiredModifierFlags: UInt64 = 0, displayName: String) {
        self.id = id
        self.triggerKeycode = triggerKeycode
        self.triggerIsModifier = triggerIsModifier
        self.requiredModifierFlags = requiredModifierFlags
        self.displayName = displayName
    }
}

enum HotkeyOption: String, CaseIterable {
    case fnKey = "fn"
    case control = "control"
    case rightOption = "rightOption"
    case rightCommand = "rightCommand"
    case hyperKey = "hyperKey"
    case ctrlOptionSpace = "ctrlOptionSpace"
    case custom = "custom"

    var keyName: String {
        switch self {
        case .fnKey: return "Fn"
        case .control: return "Left Control"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .hyperKey: return "Hyper Key – Ctrl+Opt+Cmd+Shift"
        case .ctrlOptionSpace: return "Ctrl+Option+Space"
        case .custom:
            return Self.activeCustomCombo?.displayName ?? "Custom Key"
        }
    }

    // MARK: - Custom combo UserDefaults storage

    static var savedCustomCombos: [CustomHotkeyCombo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customHotkeyCombos"),
                  let combos = try? JSONDecoder().decode([CustomHotkeyCombo].self, from: data) else {
                return []
            }
            return combos
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "customHotkeyCombos")
            }
        }
    }

    static var savedActiveCustomComboId: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: "activeCustomComboId") else { return nil }
            return UUID(uuidString: str)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: "activeCustomComboId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeCustomComboId")
            }
        }
    }

    static var activeCustomCombo: CustomHotkeyCombo? {
        guard let id = savedActiveCustomComboId else { return nil }
        return savedCustomCombos.first { $0.id == id }
    }

    var displayName: String {
        let suffix = Self.isToggleMode ? "(press twice)" : "(hold)"
        return "\(keyName) \(suffix)"
    }

    static var isToggleMode: Bool {
        get { UserDefaults.standard.bool(forKey: "hotkeyToggleMode") }
        set { UserDefaults.standard.set(newValue, forKey: "hotkeyToggleMode") }
    }

    static var saved: HotkeyOption {
        get {
            if let raw = UserDefaults.standard.string(forKey: "hotkeyOption"),
               let option = HotkeyOption(rawValue: raw) {
                return option
            }
            return .fnKey
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "hotkeyOption")
        }
    }
}
