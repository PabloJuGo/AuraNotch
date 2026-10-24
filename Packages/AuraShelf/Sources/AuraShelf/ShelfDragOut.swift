import AppKit
import SwiftUI

/// Arrastre de SALIDA de la shelf. Garantiza «el shelf nunca mueve el original» (§5.2): la sesión solo
/// ofrece `.copy`, así que Finder copia aunque sea el mismo volumen y sin Option (con `onDrag` de SwiftUI
/// no se controla la máscara y Finder movía el original).
public enum ShelfDragOut {
    /// Única operación que ofrece la shelf como origen.
    public static let operationMask: NSDragOperation = .copy

    /// Elementos del pasteboard para los ids dados: en orden de shelf, sin los ausentes (missing).
    @MainActor public static func writers(for ids: [UUID], in service: ShelfService) -> [NSPasteboardWriting] {
        service.shareURLs(ids).map { $0 as NSURL }
    }
}

/// Capa transparente sobre la tarjeta: arranca la sesión de arrastre y reenvía el clic. Solo captura el
/// botón izquierdo (hitTest); clic derecho, ctrl-clic, rueda y teclado siguen hacia la vista SwiftUI.
struct ShelfDragSource: NSViewRepresentable {
    /// Ids a arrastrar (selección completa si la tarjeta está seleccionada). Se pide al iniciar el arrastre.
    let ids: @MainActor () -> [UUID]
    let service: ShelfService
    let onClick: @MainActor (_ count: Int, _ flags: NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ShelfDragSourceView { ShelfDragSourceView() }
    func updateNSView(_ v: ShelfDragSourceView, context: Context) {
        v.ids = ids; v.service = service; v.onClick = onClick
    }
}

final class ShelfDragSourceView: NSView, NSDraggingSource {
    var ids: @MainActor () -> [UUID] = { [] }
    var service: ShelfService?
    var onClick: @MainActor (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    private var down: NSEvent?
    private var dragged = false

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let e = NSApp.currentEvent, e.type == .leftMouseDown || e.type == .leftMouseDragged || e.type == .leftMouseUp,
              !e.modifierFlags.contains(.control) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) { down = event; dragged = false }

    override func mouseUp(with event: NSEvent) {
        defer { down = nil }
        if !dragged { onClick(event.clickCount, event.modifierFlags) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = down, !dragged,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4,
              let service else { return }
        dragged = true
        let writers = ShelfDragOut.writers(for: ids(), in: service)
        guard !writers.isEmpty else { return }  // p. ej. solo ausentes: no hay nada que arrastrar
        let items = writers.enumerated().map { i, w -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: w)
            let image = Self.icon(for: w as? NSURL as URL?)
            let size = NSSize(width: 40, height: 40), o = CGFloat(min(i, 4)) * 4  // pila ligera para varios
            item.setDraggingFrame(NSRect(x: (bounds.width - size.width) / 2 + o, y: (bounds.height - size.height) / 2 - o,
                                         width: size.width, height: size.height), contents: image)
            return item
        }
        beginDraggingSession(with: items, event: start, source: self)
    }

    private static func icon(for url: URL?) -> NSImage {
        guard let url else { return NSImage() }
        if url.isFileURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        ShelfDragOut.operationMask
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }  // Option/Cmd no convierten en mover
}
