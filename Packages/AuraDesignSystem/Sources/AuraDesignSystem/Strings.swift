import AuraCore
import Foundation

/// Todas las cadenas visibles y de accesibilidad, en un solo sitio (preparadas para localizar:
/// la clave es el texto en español; al añadir un .xcstrings/.strings se resuelven por clave).
public enum Strings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    public static func moduleTitle(_ m: NotchModule) -> String {
        switch m {
        case .home: tr("Inicio")
        case .media: tr("Multimedia")
        case .shelf: tr("Estantería")
        case .calendar: tr("Calendario")
        case .widgets: tr("Widgets")
        case .clipboard: tr("Portapapeles")
        }
    }

    /// Descripción hablada de la actividad compacta (VoiceOver).
    public static func activity(_ a: ActivityKind) -> String {
        switch a {
        case .media(let playing): playing ? tr("Reproduciendo") : tr("En pausa")
        case .transfer: tr("Transferencia")
        case .timer: tr("Temporizador")
        case .alert: tr("Aviso")
        case .error: tr("Error")
        }
    }

    public static let idle = tr("Aura Notch, inactivo")
    public static let moduleNavigation = tr("Módulos")
    public static let settings = tr("Ajustes")
    public static let settingsHint = tr("Abre los ajustes de Aura Notch")
    public static let panelLabel = tr("Panel de Aura Notch")
    public static let retry = tr("Reintentar")
    public static let openSettings = tr("Abrir Ajustes del Sistema")
    public static let cause = tr("Causa")
    public static let solution = tr("Solución")

    // Estados de control
    public static let loading = tr("Cargando")
    public static let success = tr("Completado")
    public static let failure = tr("Ha fallado")
}
