import Carbon.HIToolbox

/// A single registered hot key (⌃⌥⌘P). RegisterEventHotKey only delivers this combination; it does not observe other keystrokes.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate static var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) -> OSStatus {
        unregister()
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return status }
        let id = EventHotKeyID(signature: OSType(0x5049_5042), id: 1) // "PIPB"
        status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey), id,
                                     GetApplicationEventTarget(), 0, &ref)
        return status
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
        HotKey.action = nil
    }
}
