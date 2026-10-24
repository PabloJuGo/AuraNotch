import Foundation
import AuraCore
import AuraDesignSystem

/// Política de pantalla completa (espejo de `FullscreenPolicy` de AuraNotchSurface, que este paquete no importa).
public enum FullscreenBehavior: String, Codable, Sendable, CaseIterable { case hide, keepVisible }

/// Override de movimiento de la app; `.system` respeta Reducir movimiento del sistema (§4.2.6).
public enum MotionOverride: String, Codable, Sendable, CaseIterable { case system, reduced, none }

/// Cuánto texto cabe a cada lado del notch cerrado (título de la canción, tiempo).
public enum CompactTextWidth: String, Codable, Sendable, CaseIterable {
    case narrow, normal, wide
    /// Ala a cada lado en puntos (el notch físico queda en medio).
    public var wing: Double { switch self { case .narrow: 32; case .normal: 46; case .wide: 64 } }
}

/// Idioma de la interfaz. El predeterminado es inglés (no el del sistema); el cambio se aplica al reiniciar la app.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case en, es, fr, de
    case ptBR = "pt-BR", zhHans = "zh-Hans"
    /// Cada idioma en su propio nombre, para poder encontrarlo aunque la interfaz esté en otro.
    public var nativeName: String {
        switch self {
        case .en: "English"; case .es: "Español"; case .fr: "Français"; case .de: "Deutsch"
        case .ptBR: "Português (Brasil)"; case .zhHans: "简体中文"
        }
    }

    /// Fija el idioma de la app para este proceso leyendo el ajuste guardado. Debe llamarse antes de crear `NSApplication`:
    /// Foundation fija los idiomas de `Bundle.main` la primera vez que alguien pregunta.
    public static func applyStored(from defaults: UserDefaults = .standard) {
        let stored = defaults.data(forKey: "aura.settings")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["language"] as? String
        let language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .en
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}

/// Ajustes de la app (§3.4, §5.6). Los valores por defecto son seguros: sin red, analítica ni permisos.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = AppSettings.currentSchemaVersion

    // General
    public var launchAtLogin = false
    public var mode: SurfaceMode = .notch
    // Interacción
    public var openOnClick = true
    public var openOnHover = true
    public var openOnHotKey = true
    public var hoverDelay: Double = 0.12
    public var fullscreen: FullscreenBehavior = .hide
    // Animaciones
    public var animationIntensity: Double = 1.0
    public var motionOverride: MotionOverride = .system
    // Módulos: orden completo y desactivados
    public var moduleOrder: [NotchModule] = NotchModule.allCases
    /// El portapapeles lee lo que copias: empieza apagado y se activa a propósito.
    public var disabledModules: Set<NotchModule> = [.clipboard]
    // Apariencia
    public var accentTheme: AccentTheme = .system
    public var compactTextWidth: CompactTextWidth = .normal
    public var language: AppLanguage = .en
    // Notch cerrado y gestos
    public var showCompactTitle = true
    public var swipeToSkip = true
    // Avisos propios (reunión próxima, cargador…)
    public var alertsEnabled = true
    // Red: la portada de Spotify se descarga de la URL que da Spotify
    public var loadSpotifyArtwork = true
    // Privacidad
    public var persistShelf = false
    public var historyLimit = 50

    public init() {}

    public static let hoverDelayRange = 0.0...1.0
    public static let historyLimitRange = 0...500

    /// Orden sin duplicados ni módulos perdidos: respeta el orden dado y añade los que falten.
    public static func normalizedOrder(_ order: [NotchModule]) -> [NotchModule] {
        var seen = Set<NotchModule>()
        return (order + NotchModule.allCases).filter { seen.insert($0).inserted }
    }

    /// Módulos visibles en orden.
    public var enabledModules: [NotchModule] {
        Self.normalizedOrder(moduleOrder).filter { !disabledModules.contains($0) }
    }

    /// Corrige lo corregible (orden); `false` si hay valores fuera de rango (para rechazar importaciones).
    public mutating func validate() -> Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              Self.hoverDelayRange.contains(hoverDelay),
              Self.historyLimitRange.contains(historyLimit),
              (0.0...1.0).contains(animationIntensity) else { return false }
        moduleOrder = Self.normalizedOrder(moduleOrder)
        return true
    }
}
