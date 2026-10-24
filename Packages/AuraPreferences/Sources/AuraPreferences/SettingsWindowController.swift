import AppKit
import SwiftUI

/// Ventana de ajustes nativa e independiente; un solo ejemplar reutilizado.
@MainActor public final class SettingsWindowController {
    private let store: SettingsStore
    private var window: NSWindow?

    public init(store: SettingsStore) { self.store = store }

    public func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = String(localized: "Ajustes de Aura Notch")
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
