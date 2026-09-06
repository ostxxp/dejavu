import Carbon
import Observation

/// One registered key combination, not a keyboard monitor; no Accessibility permission.
/// Owned for the application's lifetime. macOS releases registrations on termination.
@MainActor @Observable final class GlobalShortcut {
    private(set) var registrationError: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) {
        stop()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x444A5655, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else {
            registrationError = "Не удалось включить горячую клавишу. Откройте помощник из меню DéjàVu."
            return
        }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(cmdKey | shiftKey),
                                         EventHotKeyID(signature: 0x444A5655, id: 1),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if status == noErr {
            registrationError = nil
        } else {
            if let handler { RemoveEventHandler(handler); self.handler = nil }
            registrationError = "Не удалось включить ⌘⇧F: сочетание может быть занято. Освободите его и повторите попытку или откройте помощник из меню DéjàVu."
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        action = nil
    }
}
