import AppKit
import AuraPreferences
import SwiftUI

/// Ventana nativa del onboarding; un solo ejemplar reutilizado. Cualquier forma de salir (Empezar, Omitir, Esc,
/// botón de cerrar) marca el onboarding como visto: el usuario ya decidió.
@MainActor public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let state: OnboardingState
    private var window: NSWindow?
    public var onClose: (() -> Void)?

    public init(store: SettingsStore, state: OnboardingState = OnboardingState()) {
        self.store = store; self.state = state
    }

    public var isShown: Bool { window?.isVisible ?? false }

    /// Muestra (o trae al frente) la ventana. «Retorno» = ya se había visto antes.
    public func show() {
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        let returning = state.isDone
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = returning ? OnboardingStrings.windowTitleReturning : OnboardingStrings.windowTitle
        w.contentView = NSHostingView(rootView: OnboardingView(store: store, isReturning: returning) { [weak self] in self?.window?.close() })
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        state.markDone()
        window?.delegate = nil
        window = nil
        onClose?()
    }
}
