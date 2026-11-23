import Carbon.HIToolbox

/// Global shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class Hotkeys {
    struct Shortcut {
        let keyCode: Int
        let label: String
    }

    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let modifierLabel = "⌃⌥⌘"

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let me = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            if let action = me.actions[hotKey.id] { MainActor.assumeIsolated { action() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }

    func register(_ keyCode: Int, action: @escaping @MainActor () -> Void) {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_4748), id: id) // "STGH"
        guard RegisterEventHotKey(UInt32(keyCode), Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return }
        refs.append(ref)
        actions[id] = action
    }

    static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
}
