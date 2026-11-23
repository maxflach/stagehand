import AppKit
import Carbon.HIToolbox

/// A key plus Carbon modifier flags.
struct KeyCombo: Codable, Hashable {
    var keyCode: Int
    var modifiers: UInt32

    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    init(_ keyCode: Int, modifiers: UInt32 = KeyCombo.defaultModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = Int(event.keyCode)
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        modifiers = mods
    }

    var modifierLabel: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    var keyLabel: String { Self.keyName(keyCode) }
    var label: String { modifierLabel + keyLabel }

    var menuFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Function keys work alone; anything else needs ⌘, ⌃ or ⌥, or it would swallow normal typing.
    var isUsable: Bool {
        let strong = UInt32(controlKey | optionKey | cmdKey)
        return modifiers & strong != 0 || Self.functionKeys.contains(keyCode)
    }

    private static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                                 kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                                                 kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    private static let special: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The character the key types on the current keyboard layout, so a Swedish keyboard shows its own keys.
    static func keyName(_ code: Int) -> String {
        if let name = special[code] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Everything a global shortcut can do.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case favorite1, favorite2, favorite3, favorite4, favorite5, favorite6, favorite7, favorite8, favorite9
    case previous, next, refresh
    case split, follow, zoom, zoomIn, zoomOut
    case spotlight, highlight
    case camera, justMe
    case beRightBack, breakTime, nameTag

    var id: String { rawValue }

    /// Slot index for the favourite actions.
    var favoriteSlot: Int? {
        let all: [ShortcutAction] = [.favorite1, .favorite2, .favorite3, .favorite4, .favorite5,
                                     .favorite6, .favorite7, .favorite8, .favorite9]
        return all.firstIndex(of: self)
    }

    static func favorite(_ slot: Int) -> ShortcutAction {
        [.favorite1, .favorite2, .favorite3, .favorite4, .favorite5, .favorite6, .favorite7, .favorite8, .favorite9][slot]
    }

    var title: String {
        if let slot = favoriteSlot { return "Favourite \(slot + 1)" }
        switch self {
        case .previous: return "Previous favourite"
        case .next: return "Next favourite"
        case .refresh: return "Refresh the window list"
        case .split: return "Side by side on / off"
        case .follow: return "Follow mode on / off"
        case .zoom: return "Zoom on / off"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .spotlight: return "Spotlight on / off"
        case .highlight: return "Highlight pointer on / off"
        case .camera: return "Webcam on / off"
        case .justMe: return "Just me: webcam full screen"
        case .beRightBack: return "Be right back card"
        case .breakTime: return "Start / stop break countdown"
        case .nameTag: return "Name tag on / off"
        default: return rawValue
        }
    }

    var group: String {
        if favoriteSlot != nil { return "Favourites" }
        switch self {
        case .previous, .next, .refresh: return "Favourites"
        case .split, .follow, .zoom, .zoomIn, .zoomOut: return "Stage"
        case .spotlight, .highlight: return "Pointer"
        case .camera, .justMe: return "Webcam"
        default: return "Cards"
        }
    }

    static let groups = ["Favourites", "Stage", "Pointer", "Webcam", "Cards"]

    var defaultCombo: KeyCombo {
        if let slot = favoriteSlot {
            return KeyCombo([kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                             kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9][slot])
        }
        switch self {
        case .previous: return KeyCombo(kVK_LeftArrow)
        case .next: return KeyCombo(kVK_RightArrow)
        case .refresh: return KeyCombo(kVK_ANSI_R)
        case .split: return KeyCombo(kVK_ANSI_D)
        case .follow: return KeyCombo(kVK_ANSI_F)
        case .zoom: return KeyCombo(kVK_ANSI_Z)
        case .zoomIn: return KeyCombo(kVK_ANSI_Equal)
        case .zoomOut: return KeyCombo(kVK_ANSI_Minus)
        case .spotlight: return KeyCombo(kVK_ANSI_S)
        case .highlight: return KeyCombo(kVK_ANSI_H)
        case .camera: return KeyCombo(kVK_ANSI_C)
        case .justMe: return KeyCombo(kVK_ANSI_J)
        case .beRightBack: return KeyCombo(kVK_ANSI_W)
        case .breakTime: return KeyCombo(kVK_ANSI_B)
        case .nameTag: return KeyCombo(kVK_ANSI_L)
        default: return KeyCombo(kVK_F20)
        }
    }

    // MARK: Storage

    private static let key = "shortcuts"

    /// Current shortcuts; an action missing from the map has no shortcut.
    static func load() -> [ShortcutAction: KeyCombo] {
        var map = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultCombo) })
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: KeyCombo?].self, from: data) else { return map }
        for (name, combo) in saved {
            guard let action = ShortcutAction(rawValue: name) else { continue }
            map[action] = combo
        }
        return map
    }

    /// Saves only what differs from the defaults, so new actions in later versions get their default.
    static func save(_ map: [ShortcutAction: KeyCombo]) {
        var changed: [String: KeyCombo?] = [:]
        for action in allCases where map[action] != action.defaultCombo {
            changed[action.rawValue] = map[action]
        }
        if changed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(changed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
