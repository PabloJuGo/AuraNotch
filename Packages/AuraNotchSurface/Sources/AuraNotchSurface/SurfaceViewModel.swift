import SwiftUI
import Observation
import AuraCore

/// Estado visual que el controlador publica hacia las vistas SwiftUI (único canal: sin lógica en las vistas).
/// `progress` cambia en cada fotograma de la transición: las vistas reales deben leerlo solo donde
/// lo necesiten (regla §4.2.9, sin recalcular el árbol completo).
@MainActor @Observable public final class SurfaceViewModel {
    public var progress: Double = 0
    public var state: SurfaceState = .hidden
    public var motion: MotionPreference = .full
    /// Rects en coordenadas globales: ventana actual, reposo y expandido.
    public var windowFrame: CGRect = .zero
    public var restFrame: CGRect = .zero
    public var expandedFrame: CGRect = .zero

    public init() {}

    /// Rect de la superficie visible, relativo a la ventana y con origen arriba-izquierda
    /// (la superficie siempre cuelga del borde superior).
    public var shapeRect: CGRect {
        // Con Reduce Motion no hay morph: se salta al destino (el fundido lo aporta el contenido).
        let p: Double
        if motion == .full { p = progress } else { p = progress >= 0.5 ? 1 : 0 }
        let r = NotchGeometry.lerp(restFrame, expandedFrame, p)
        return CGRect(x: r.minX - windowFrame.minX, y: 0, width: r.width, height: r.height)
    }
}

/// Contenido provisional: cápsula/panel negro. DESIGN lo sustituye mediante `SurfaceContentFactory`.
public struct SurfacePlaceholderView: View {
    let model: SurfaceViewModel
    public init(model: SurfaceViewModel) { self.model = model }

    public var body: some View {
        let r = model.shapeRect
        let radius = 10 + 18 * model.progress
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                               bottomTrailingRadius: radius, topTrailingRadius: 0)
            .fill(.black)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea() // la ventana cubre la zona del notch: sin insets
    }
}

/// Punto de inyección del contenido real.
public typealias SurfaceContentFactory = @MainActor (SurfaceViewModel) -> AnyView
