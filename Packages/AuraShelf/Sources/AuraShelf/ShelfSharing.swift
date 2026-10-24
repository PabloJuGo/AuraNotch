import AppKit
import SwiftUI

/// Presenta `NSSharingServicePicker` anclado a una vista. El host puede usarlo con
/// `ShelfService.shareURLs(_:)` y cualquier NSView propia.
@MainActor
public enum ShelfSharing {
    private static var current: NSSharingServicePicker?

    public static func present(_ urls: [URL], relativeTo view: NSView) {
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        current = picker  // el picker debe seguir vivo mientras el menú está abierto
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// Servicio de envío por AirDrop; `NSSharingService` ya lo cumple. Protocolo para sustituirlo en pruebas
/// (el selector real no se abre en tests).
@MainActor
public protocol ShelfAirDropService: AnyObject {
    var delegate: NSSharingServiceDelegate? { get set }
    func canPerform(withItems items: [Any]?) -> Bool
    func perform(withItems items: [Any])
}
extension NSSharingService: ShelfAirDropService {}

/// Envío por AirDrop (`.sendViaAirDrop`) de elementos de la shelf, solo referencias de lectura.
@MainActor
public enum ShelfAirDrop {
    /// Fábrica del servicio; las pruebas la sustituyen por un doble.
    public static var makeService: () -> ShelfAirDropService? = { NSSharingService(named: .sendViaAirDrop) }
    private static var session: Session?

    /// false si AirDrop no existe o no puede enviar esos elementos (p. ej. desactivado en el sistema).
    public static func isAvailable(_ urls: [URL]) -> Bool {
        guard let service = makeService() else { return false }
        return urls.isEmpty || service.canPerform(withItems: urls)
    }

    /// Abre el selector de AirDrop junto a `view`. No activa la app: el panel es no activante y robarle
    /// el foco rompería su orden Z.
    @discardableResult
    public static func send(_ urls: [URL], from view: NSView? = nil) -> Bool {
        guard !urls.isEmpty, let service = makeService(), service.canPerform(withItems: urls) else { return false }
        let s = Session(service: service, anchor: view)
        session = s  // el delegado es débil en NSSharingService: sin esta referencia moriría antes de terminar
        service.delegate = s
        service.perform(withItems: urls)
        return true
    }

    @MainActor
    private final class Session: NSObject, NSSharingServiceDelegate {
        let service: ShelfAirDropService
        weak var anchor: NSView?

        init(service: ShelfAirDropService, anchor: NSView?) { self.service = service; self.anchor = anchor }

        private func finish() { if ShelfAirDrop.session === self { ShelfAirDrop.session = nil } }

        func sharingService(_ s: NSSharingService, didShareItems items: [Any]) { finish() }
        func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish() }

        // Coloca el selector junto al panel en lugar de al centro de la pantalla.
        func sharingService(_ s: NSSharingService, sourceWindowForShareItems items: [Any],
                            sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
            anchor?.window
        }

        func sharingService(_ s: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
            guard let a = anchor, let w = a.window else { return .zero }
            return w.convertToScreen(a.convert(a.bounds, to: nil))
        }
    }
}

/// Ancla invisible: al recibir URLs en el binding, muestra el picker (o AirDrop) y vacía el binding.
struct ShareAnchor: NSViewRepresentable {
    @Binding var urls: [URL]
    var airDrop = false

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard !urls.isEmpty else { return }
        let pending = urls
        Task { @MainActor in
            urls = []
            if airDrop { ShelfAirDrop.send(pending, from: view) } else { ShelfSharing.present(pending, relativeTo: view) }
        }
    }
}
