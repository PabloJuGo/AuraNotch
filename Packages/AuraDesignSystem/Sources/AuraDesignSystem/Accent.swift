import SwiftUI

/// Color de acento elegido por el usuario (tema). `system` usa el de macOS; el resto son colores fijos legibles sobre negro.
public enum AccentTheme: String, CaseIterable, Codable, Sendable {
    case system, blue, purple, pink, red, orange, green, graphite

    public var rgb: RGB? {
        switch self {
        case .system: nil
        case .blue: RGB(0.04, 0.52, 1.0)
        case .purple: RGB(0.75, 0.35, 0.95)
        case .pink: RGB(1.0, 0.31, 0.55)
        case .red: RGB(1.0, 0.27, 0.23)
        case .orange: RGB(1.0, 0.62, 0.04)
        case .green: RGB(0.19, 0.82, 0.35)
        case .graphite: RGB(0.68, 0.68, 0.70)
        }
    }

    public var color: Color { rgb.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .accentColor }

    public var title: String {
        switch self {
        case .system: String(localized: "Sistema")
        case .blue: String(localized: "Azul")
        case .purple: String(localized: "Morado")
        case .pink: String(localized: "Rosa")
        case .red: String(localized: "Rojo")
        case .orange: String(localized: "Naranja")
        case .green: String(localized: "Verde")
        case .graphite: String(localized: "Grafito")
        }
    }
}

private struct AuraAccentKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension EnvironmentValues {
    /// Acento del tema; `nil` = el de siempre (sin tema).
    public var auraAccent: Color? {
        get { self[AuraAccentKey.self] }
        set { self[AuraAccentKey.self] = newValue }
    }
}
