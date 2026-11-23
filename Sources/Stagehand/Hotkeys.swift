import Carbon.HIToolbox

/// Global shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class Hotkeys {
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
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Returns false when the combination is taken, usually by another app.
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping @MainActor () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_4748), id: id) // "STGH"
        guard RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs.append(ref)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}
