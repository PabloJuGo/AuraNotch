import SwiftUI

/// Silueta que se funde con el notch: las esquinas superiores se «abren» hacia el borde de la
/// pantalla (empalme cóncavo) y las inferiores son convexas. El rect incluye los empalmes
/// laterales, de ancho `topRadius` a cada lado del cuerpo.
/// Los radios se interpolan (`animatableData`); el tamaño lo interpola el layout/frame.
/// Se recortan al rect actual para no generar artefactos con tamaños intermedios.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Cápsula compacta: empalme pequeño, parte inferior totalmente redondeada.
    public static func compact(height: CGFloat, topRadius: CGFloat = 6) -> NotchShape {
        NotchShape(topRadius: topRadius, bottomRadius: Radius.compact(height: height))
    }

    public static let expanded = NotchShape(topRadius: 14, bottomRadius: Radius.panel)

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    /// Radios efectivos tras recortar al rect (público para pruebas).
    public func clampedRadii(in rect: CGRect) -> (top: CGFloat, bottom: CGFloat) {
        let tr = max(0, min(topRadius, rect.width / 2, rect.height))
        let br = max(0, min(bottomRadius, rect.width / 2 - tr, rect.height - tr))
        return (tr, br)
    }

    public func path(in rect: CGRect) -> Path {
        let (tr, br) = clampedRadii(in: rect)
        let l = rect.minX + tr, r = rect.maxX - tr
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Empalme superior izquierdo (cóncavo) y lado izquierdo.
        p.addArc(tangent1End: CGPoint(x: l, y: rect.minY), tangent2End: CGPoint(x: l, y: rect.minY + tr), radius: tr)
        // Esquina inferior izquierda (convexa).
        p.addArc(tangent1End: CGPoint(x: l, y: rect.maxY), tangent2End: CGPoint(x: l + br, y: rect.maxY), radius: br)
        p.addArc(tangent1End: CGPoint(x: r, y: rect.maxY), tangent2End: CGPoint(x: r, y: rect.maxY - br), radius: br)
        // Lado derecho y empalme superior derecho.
        p.addArc(tangent1End: CGPoint(x: r, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: tr)
        p.closeSubpath()
        return p
    }
}
