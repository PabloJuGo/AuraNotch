import AppKit
import AuraCore
import SwiftUI

// Tokens de diseño. Valores INICIALES a validar en hardware real;
// no son valores oficiales de Apple.

/// Retícula base de 4 pt (§3.1).
public enum Space {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let all: [CGFloat] = [xs, sm, md, lg, xl]
}

public enum Radius {
    public static let panel: CGFloat = 20
    public static let control: CGFloat = 10
    /// Compacto = cápsula: el radio inferior es la mitad del alto disponible.
    public static func compact(height: CGFloat) -> CGFloat { height / 2 }
}

// MARK: - Color

/// Color sRGB opaco. Se mantiene explícito (no `Color`) para poder medir contraste.
public struct RGB: Equatable, Sendable {
    public let r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(white: Double) { self.init(white, white, white) }

    /// Luminancia relativa WCAG 2.x.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Ratio de contraste WCAG (1...21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// Color semántico con variante por apariencia del sistema (claro/oscuro) y alto contraste.
public struct TokenColor: Equatable, Sendable {
    public enum Variant: CaseIterable, Sendable { case light, dark, lightHighContrast, darkHighContrast }

    let values: [Variant: RGB]

    public init(light: RGB, dark: RGB, lightHighContrast: RGB, darkHighContrast: RGB) {
        values = [.light: light, .dark: dark, .lightHighContrast: lightHighContrast, .darkHighContrast: darkHighContrast]
    }

    /// El notch es negro en cualquier apariencia del sistema: claro == oscuro por diseño.
    /// El eje claro/oscuro existe para poder divergir (p. ej. modo flotante) sin cambiar la API.
    public init(standard: RGB, highContrast: RGB) {
        self.init(light: standard, dark: standard, lightHighContrast: highContrast, darkHighContrast: highContrast)
    }

    public func rgb(_ v: Variant) -> RGB { values[v]! }

    /// Color dinámico: se resuelve según la apariencia efectiva de la vista.
    public var color: Color { Color(nsColor: nsColor) }

    public var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let v = Self.variant(for: appearance)
            let c = rgb(v)
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
    }

    public static func variant(for appearance: NSAppearance) -> Variant {
        variant(named: appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]))
    }

    public static func variant(named name: NSAppearance.Name?) -> Variant {
        switch name {
        case .darkAqua?: .dark
        case .accessibilityHighContrastAqua?: .lightHighContrast
        case .accessibilityHighContrastDarkAqua?: .darkHighContrast
        default: .light
        }
    }
}

public enum AuraColor {
    /// Superficie del notch: negro puro, para fundirse con el hardware.
    public static let surface = TokenColor(standard: RGB(white: 0), highContrast: RGB(white: 0))
    public static let elevatedSurface = TokenColor(standard: RGB(white: 0.11), highContrast: RGB(white: 0.17))
    /// Relleno de control pulsado (un escalón sobre `elevatedSurface`).
    public static let pressedSurface = TokenColor(standard: RGB(white: 0.20), highContrast: RGB(white: 0.26))
    public static let primaryText = TokenColor(standard: RGB(white: 1), highContrast: RGB(white: 1))
    public static let secondaryText = TokenColor(standard: RGB(white: 0.68), highContrast: RGB(white: 0.85))
    public static let separator = TokenColor(standard: RGB(white: 0.24), highContrast: RGB(white: 0.52))
    public static let accent = TokenColor(standard: RGB(0.04, 0.52, 1.0), highContrast: RGB(0.35, 0.68, 1.0))
    public static let warning = TokenColor(standard: RGB(1.0, 0.62, 0.04), highContrast: RGB(1.0, 0.72, 0.30))
    public static let destructive = TokenColor(standard: RGB(1.0, 0.27, 0.23), highContrast: RGB(1.0, 0.45, 0.42))
    /// Añadido a los 8 de §3.2: necesario para el estado de control `success`.
    public static let success = TokenColor(standard: RGB(0.19, 0.82, 0.35), highContrast: RGB(0.40, 0.90, 0.52))

    /// Textos/iconos que deben leerse sobre `surface` y `elevatedSurface`.
    public static let foregrounds: [(name: String, token: TokenColor)] = [
        ("primaryText", primaryText), ("secondaryText", secondaryText), ("accent", accent),
        ("warning", warning), ("destructive", destructive), ("success", success),
    ]
}

// MARK: - Tipografía

/// Fuentes del sistema (San Francisco). Nota: macOS no tiene Dynamic Type; los estilos
/// de texto de SwiftUI dan tamaños fijos del sistema. Validar legibilidad en hardware.
public enum AuraFont {
    public static let moduleTitle = Font.headline
    public static let body = Font.callout
    public static let secondary = Font.caption
    public static let compact = Font.caption.weight(.medium)
    public static let numeric = Font.caption.monospacedDigit()
}

// MARK: - Movimiento

/// Especificación pura de una animación; la duración sale SIEMPRE de `Transition` (AuraCore).
public struct MotionSpec: Equatable, Sendable {
    public enum Curve: Equatable, Sendable { case spring, fade, instant }
    public let curve: Curve
    public let duration: TimeInterval
    /// 0 = amortiguación crítica (sin overshoot).
    public let bounce: Double
}

public enum Motion {
    public static func spec(_ t: AuraCore.Transition, _ p: MotionPreference) -> MotionSpec {
        switch p {
        case .full: MotionSpec(curve: .spring, duration: t.duration(for: p), bounce: 0)
        case .reduced: MotionSpec(curve: .fade, duration: t.duration(for: p), bounce: 0)
        case .none: MotionSpec(curve: .instant, duration: 0, bounce: 0)
        }
    }

    /// nil = sin animación (Reduce Motion «ninguna»).
    public static func animation(_ t: AuraCore.Transition, _ p: MotionPreference) -> Animation? {
        let s = spec(t, p)
        switch s.curve {
        case .spring: return .spring(duration: s.duration, bounce: s.bounce)
        case .fade: return .easeOut(duration: s.duration)
        case .instant: return nil
        }
    }

    /// Entrada/salida de contenido: con movimiento reducido solo fundido (AN-12).
    public static func contentTransition(_ p: MotionPreference) -> AnyTransition {
        p == .full ? .opacity.combined(with: .scale(scale: 0.97, anchor: .top)) : .opacity
    }
}

extension MotionPreference {
    /// Ajuste de la app (si lo hay) manda sobre el del sistema.
    public static func resolve(override: MotionPreference?, systemReduceMotion: Bool) -> MotionPreference {
        override ?? (systemReduceMotion ? .reduced : .full)
    }
}

private struct AuraMotionKey: EnvironmentKey { static let defaultValue: MotionPreference? = nil }

extension EnvironmentValues {
    /// Preferencia inyectada por el MotionCoordinator; nil = seguir Reduce Motion del sistema.
    public var auraMotion: MotionPreference? {
        get { self[AuraMotionKey.self] }
        set { self[AuraMotionKey.self] = newValue }
    }
}

private struct AuraPanelOpenKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// false con el panel colapsado: el contenido sigue vivo pero oculto y no debe tener relojes ni refrescos.
    public var auraPanelOpen: Bool {
        get { self[AuraPanelOpenKey.self] }
        set { self[AuraPanelOpenKey.self] = newValue }
    }
}

/// Lee la preferencia efectiva dentro de una vista: `let motion = MotionEnvironment()`.
struct MotionEnvironment: DynamicProperty {
    @Environment(\.auraMotion) private var override
    @Environment(\.accessibilityReduceMotion) private var reduce
    var value: MotionPreference { .resolve(override: override, systemReduceMotion: reduce) }
}
