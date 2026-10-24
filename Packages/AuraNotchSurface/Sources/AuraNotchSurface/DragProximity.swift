import AppKit

/// Reglas puras del aviso de arrastre (públicas para poder probarlas).
public enum DragProximity {
    /// ¿Este movimiento es un arrastre de archivos dentro de la zona de aviso?
    public static func isFileDragInZone(point: CGPoint, zone: CGRect?, changeCount: Int, baseline: Int, hasFiles: Bool) -> Bool {
        guard let zone, changeCount != baseline, hasFiles else { return false }
        return zone.contains(point)
    }

    /// Zona de aviso: la silueta en reposo ampliada a los lados y hacia abajo (coordenadas AppKit, origen abajo-izquierda).
    public static func zone(around rest: CGRect, margin: CGFloat = 80, depth: CGFloat = 110) -> CGRect {
        CGRect(x: rest.minX - margin, y: rest.maxY - depth, width: rest.width + 2 * margin, height: depth + 1)
    }
}

/// Detecta un arrastre de archivos de otra app que se acerca al notch y abre el panel ANTES de que el puntero llegue
/// al borde superior: allí macOS activa Mission Control y se queda con el arrastre (medido con un arrastre real de Finder).
/// Solo escucha mientras hay un botón pulsado; sin arrastre no hace nada (sin polling ni temporizadores).
@MainActor final class DragProximityMonitor {
    /// Inyectables en pruebas.
    var pasteboard: () -> (changeCount: Int, hasFiles: Bool) = {
        let pb = NSPasteboard(name: .drag)
        return (pb.changeCount, pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
    }
    var pointer: () -> CGPoint = { NSEvent.mouseLocation }

    private let zone: @MainActor () -> CGRect?
    private let onApproach: @MainActor () -> Void
    private let onEnd: @MainActor () -> Void
    private var monitors: [Any] = []
    private var baseline = 0
    private(set) var engaged = false

    init(zone: @escaping @MainActor () -> CGRect?, onApproach: @escaping @MainActor () -> Void, onEnd: @escaping @MainActor () -> Void) {
        self.zone = zone; self.onApproach = onApproach; self.onEnd = onEnd
    }

    func start() {
        guard monitors.isEmpty else { return }
        syncBaseline()
        func add(_ mask: NSEvent.EventTypeMask, _ body: @escaping @MainActor (DragProximityMonitor) -> Void) {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            }) { monitors.append(m) }
        }
        add(.leftMouseDragged) { $0.moved() }
        add(.leftMouseUp) { $0.released() }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        engaged = false
    }

    func moved() {
        guard !engaged else { return }
        let pb = pasteboard()
        guard DragProximity.isFileDragInZone(point: pointer(), zone: zone(), changeCount: pb.changeCount, baseline: baseline, hasFiles: pb.hasFiles) else { return }
        engaged = true
        capturedURLs = fileURLs()
        onApproach()
    }

    /// Archivos del arrastre en curso, leídos al detectarlo (al soltar, el sistema ya vacía el portapapeles de arrastre).
    /// Respaldo para cuando el panel no llega a recibir el soltado.
    private(set) var capturedURLs: [URL] = []

    private func fileURLs() -> [URL] {
        (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Fin de cualquier interacción con el ratón: el contenido que quede en el portapapeles de arrastre ya no es un arrastre vivo.
    /// (Finder lo escribe antes de que llegue el evento de pulsación, por eso la referencia se toma al soltar, no al pulsar.)
    func syncBaseline() { baseline = pasteboard().changeCount }

    func released() {
        syncBaseline()
        guard engaged else { return }
        engaged = false
        onEnd()
    }
}
