import CoreGraphics

public enum SwipeDirection: Equatable, Sendable { case previous, next }

/// Reglas puras del deslizamiento de dos dedos sobre el notch cerrado (públicas para poder probarlas).
/// Un gesto = una acción: tras disparar, se ignora el resto hasta que acaba (sin repeticiones por inercia).
public struct SwipeDetector: Sendable {
    public enum Phase: Sendable { case began, changed, ended }

    /// Distancia horizontal acumulada (puntos) para disparar.
    public var threshold: CGFloat
    private var dx: CGFloat = 0, dy: CGFloat = 0
    private var locked = false

    public init(threshold: CGFloat = 40) { self.threshold = threshold }

    /// `dx`/`dy`: movimiento de los DEDOS (derecha = positivo). Devuelve la dirección al cruzar el umbral.
    public mutating func feed(dx ddx: CGFloat, dy ddy: CGFloat, phase: Phase) -> SwipeDirection? {
        if phase == .began { self = SwipeDetector(threshold: threshold) }
        defer { if phase == .ended { self = SwipeDetector(threshold: threshold) } }
        guard !locked else { return nil }
        dx += ddx; dy += ddy
        // Gesto vertical (scroll normal): se descarta entero, aunque luego derive en horizontal.
        if abs(dy) >= threshold, abs(dy) > abs(dx) { locked = true; return nil }
        guard abs(dx) >= threshold, abs(dx) > 2 * abs(dy) else { return nil }
        locked = true
        return dx > 0 ? .previous : .next
    }
}
