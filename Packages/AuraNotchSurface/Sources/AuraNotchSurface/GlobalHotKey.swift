import Carbon.HIToolbox

/// Atajo global vía Carbon `RegisterEventHotKey`: no requiere permisos de Accesibilidad ni Monitorización de entrada.
@MainActor final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    /// `nil` si el sistema rechaza el registro (p. ej. combinación ya usada).
    init?(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.action?() } // Carbon entrega en el hilo principal
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handler) == noErr else { return nil }
        let id = EventHotKeyID(signature: 0x4155_5241 /* 'AURA' */, id: 1)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
        else { RemoveEventHandler(handler); return nil }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil; Self.action = nil
    }
}
