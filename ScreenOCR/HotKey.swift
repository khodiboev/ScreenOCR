import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Works in every app and needs no extra permission.
@MainActor
final class HotKey {
    // Default shortcut: ⌥S (Option + S).
    // To change it, pick another key code (e.g. kVK_ANSI_X) or modifier (e.g. controlKey).
    static let defaultKeyCode = UInt32(kVK_ANSI_S)
    static let defaultModifiers = UInt32(optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot key events on the main thread
            MainActor.assumeIsolated {
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().fire()
            }
            return noErr
        }, 1, &eventType, userData, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F43_5231), id: 1)   // "OCR1"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func fire() {
        action()
    }
}
