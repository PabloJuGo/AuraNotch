import AppKit
import SwiftUI

/// Panel sin marco, no activante: no roba el foco a la app en primer plano.
final class SurfacePanel: NSPanel {
    /// Solo `true` cuando el contenido necesita teclado (p. ej. campo de texto o Escape).
    var allowsKey = false
    /// Teclas del panel; devuelve `true` si las consumió.
    var onKeyDown: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        // Por encima de la barra de menús (.mainMenu = 24): cubre la franja del notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    // AppKit empuja las ventanas fuera de la barra de menús; aquí queremos justo ahí.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Antes de SwiftUI: Escape y flechas funcionan aunque un control tenga el foco, salvo mientras se edita texto.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !(firstResponder is NSText), onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    /// ⌘+tecla: sin menú principal no estorba, pero así los atajos del panel llegan antes de que AppKit los busque.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, !(firstResponder is NSText), onKeyDown?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Vista raíz: tracking de ratón, clics sobre la zona compacta y destino de arrastre de archivos.
final class SurfaceContentView: NSView {
    var interceptsClicks = true
    var onEnter: () -> Void = {}, onExit: () -> Void = {}, onClick: () -> Void = {}
    var onDragEnter: () -> Void = {}, onDragExit: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }
    var onSwipe: (SwipeDirection) -> Void = { _ in }
    private var swipe = SwipeDetector()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: la app es "accessory" y casi nunca está activa.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
    override func mouseDown(with event: NSEvent) { onClick() }
    /// Dos dedos en el trackpad (con fase). La rueda del ratón y la inercia no traen fase de gesto: se ignoran.
    override func scrollWheel(with event: NSEvent) {
        let phase: SwipeDetector.Phase
        switch event.phase {
        case [.began], [.mayBegin]: phase = .began
        case [.changed], [.stationary]: phase = .changed
        case [.ended], [.cancelled]: phase = .ended
        default: return super.scrollWheel(with: event)
        }
        // scrollingDelta sigue al contenido: con desplazamiento natural coincide con los dedos, sin él es el opuesto.
        let k: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        if let d = swipe.feed(dx: event.scrollingDeltaX * k, dy: event.scrollingDeltaY * k, phase: phase) { onSwipe(d) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Con el panel plegado el clic es de la superficie; expandido, del contenido SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return interceptsClicks && hit != nil ? self : hit
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] } // arrastre no válido: no mueve la máquina
        onDragEnter()
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExit() }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
