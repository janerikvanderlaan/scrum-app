import Carbon

/// Control-Option-C anywhere: "coach me on the field I'm in".
/// Carbon hot keys need no extra permission.
enum HotKey {
    private static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(_ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434F_4348), id: 1) // "COCH"
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
