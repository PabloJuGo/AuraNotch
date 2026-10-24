import CoreGraphics
import AuraCore

/// Medidas de una pantalla, desacopladas de `NSScreen` para poder probar la
/// geometría con pantallas sintéticas. Coordenadas globales AppKit (origen abajo-izquierda).
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `safeAreaInsets.top`: >0 solo si hay cámara/notch.
    public var safeAreaTop: CGFloat
    public var auxTopLeft: CGRect?
    public var auxTopRight: CGRect?
    public var scale: CGFloat

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxTopLeft: CGRect? = nil, auxTopRight: CGRect? = nil, scale: CGFloat = 2) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.safeAreaTop = safeAreaTop
        self.auxTopLeft = auxTopLeft; self.auxTopRight = auxTopRight; self.scale = scale
    }

    /// Las áreas auxiliares de NSScreen no documentan si son locales o globales:
    /// si no caen dentro del frame, se asumen locales y se desplazan al origen de la pantalla.
    private func global(_ r: CGRect) -> CGRect {
        frame.contains(CGPoint(x: r.midX, y: r.midY)) ? r : r.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Hueco físico de la cámara, deducido del espacio entre las dos áreas auxiliares.
    /// `nil` si la pantalla no tiene notch (o los datos son incoherentes).
    public var notchRect: CGRect? {
        guard safeAreaTop > 0, let l = auxTopLeft.map(global), let r = auxTopRight.map(global),
              r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: frame.maxY - safeAreaTop, width: r.minX - l.maxX, height: safeAreaTop)
    }
}

/// Tamaños deseados (antes de recortar a la pantalla).
public struct SurfaceSizes: Equatable, Sendable {
    /// Ancho extra a cada lado del notch en el estado compacto con actividad: siempre el mismo y simétrico (no depende del texto).
    public var wing: CGFloat = 46
    public var floatingIdle = CGSize(width: 120, height: 28)
    public var floatingCompact = CGSize(width: 260, height: 32)
    public var expanded = CGSize(width: 600, height: 380)
    /// Separación bajo la barra de menús en modo flotante.
    public var floatingTopGap: CGFloat = 6
    public init() {}
}

/// Rectángulos finales (coordenadas globales) de cada estado de reposo/expandido.
/// Todos anclados arriba-centro: `idle` ⊂ `compact` ⊂ `expanded` en el eje horizontal.
public struct SurfaceLayout: Equatable, Sendable {
    /// Modo efectivo tras resolver (nunca `.disabledOnExternalDisplay`).
    public var mode: SurfaceMode
    public var idle: CGRect
    public var compact: CGRect
    public var expanded: CGRect
}

/// Cálculo puro de geometría (§3.3). Sin acceso a AppKit ni coordenadas "mágicas" del notch.
public enum NotchGeometry {
    /// `nil` = superficie deshabilitada en esta pantalla (modo `disabledOnExternalDisplay` sin notch,
    /// o pantalla sin área útil).
    public static func layout(for m: ScreenMetrics, requested: SurfaceMode,
                              sizes: SurfaceSizes = SurfaceSizes()) -> SurfaceLayout? {
        let notch = m.notchRect
        switch (requested, notch) {
        case (.notch, let n?), (.disabledOnExternalDisplay, let n?):
            // El panel puede usar todo el ancho físico y llegar hasta el fondo visible (sin Dock).
            let top = m.frame.maxY
            guard let bounds = area(x: m.frame.minX, y: m.visibleFrame.minY, width: m.frame.width, height: top - m.visibleFrame.minY)
            else { return nil }
            func place(_ s: CGSize) -> CGRect { anchoredTop(s, centerX: n.midX, top: top, bounds: bounds, scale: m.scale) }
            return SurfaceLayout(
                mode: .notch,
                idle: place(n.size),
                compact: place(CGSize(width: n.width + 2 * sizes.wing, height: n.height)),
                expanded: place(sizes.expanded))
        case (.disabledOnExternalDisplay, nil):
            return nil
        case (.notch, nil), (.topCenterFloating, _):
            let top = m.visibleFrame.maxY - sizes.floatingTopGap
            guard let bounds = area(x: m.visibleFrame.minX, y: m.visibleFrame.minY, width: m.visibleFrame.width, height: top - m.visibleFrame.minY)
            else { return nil }
            func place(_ s: CGSize) -> CGRect { anchoredTop(s, centerX: m.frame.midX, top: top, bounds: bounds, scale: m.scale) }
            return SurfaceLayout(
                mode: .topCenterFloating,
                idle: place(sizes.floatingIdle),
                compact: place(sizes.floatingCompact),
                expanded: place(sizes.expanded))
        }
    }

    /// `CGRect.height` devuelve el valor absoluto: hay que validar el signo ANTES de construir el rect.
    private static func area(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect? {
        width > 0 && height > 0 ? CGRect(x: x, y: y, width: width, height: height) : nil
    }

    /// Rect de tamaño `size` colgando de `top`, centrado en `centerX`, recortado y desplazado para caber en `bounds`.
    static func anchoredTop(_ size: CGSize, centerX: CGFloat, top: CGFloat, bounds: CGRect, scale: CGFloat) -> CGRect {
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let w = snap(min(size.width, bounds.width))
        let h = snap(min(size.height, top - bounds.minY))
        let x = snap(min(max(centerX - w / 2, bounds.minX), bounds.maxX - w))
        return CGRect(x: x, y: top - h, width: w, height: h)
    }

    /// Interpola dos rects (progreso 0…1 de compacto a expandido). Sin overshoot: se acota.
    public static func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        let t = CGFloat(min(max(p, 0), 1))
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}
