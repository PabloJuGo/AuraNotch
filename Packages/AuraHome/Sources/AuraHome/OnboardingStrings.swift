import Foundation

enum OnboardingStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let windowTitle = tr("Bienvenido a Aura Notch")
    static let windowTitleReturning = tr("Aura Notch: introducción")
    static func stepOf(_ i: Int, _ n: Int) -> String { String(localized: "Paso \(i) de \(n)") }

    static let welcomeTitle = tr("Tu notch, más útil")
    static let welcomeTitleReturning = tr("Qué hace Aura Notch")
    static let welcomeBody = tr("Aura Notch convierte la zona del notch en un panel discreto: controla lo que suena, deja archivos en una estantería temporal, consulta tu próximo evento y usa un temporizador, sin abrir ninguna app.")
    static let welcomeQuiet = tr("Permanece en silencio hasta que lo necesitas: no roba el foco ni muestra avisos por su cuenta.")

    static let privacyTitle = tr("Tus datos se quedan contigo")
    static let privacyLocal = tr("Todo es local: sin cuenta, sin red y sin telemetría.")
    static let privacyPermissions = tr("Los permisos son opcionales. Aura Notch nunca los pide aquí: macOS preguntará solo cuando uses cada función por primera vez.")
    static let privacyCalendarTitle = tr("Calendario")
    static let privacyCalendarBody = tr("Solo lectura, para mostrar tus próximos eventos. Se pide al abrir el módulo Calendario.")
    static let privacyMediaTitle = tr("Música y Spotify")
    static let privacyMediaBody = tr("Ver qué suena no necesita permiso. Pausar o saltar pide «Automatización» la primera vez que lo uses.")

    static let modulesTitle = tr("Elige tus módulos")
    static let modulesBody = tr("Activa solo lo que quieras. Puedes cambiarlo cuando quieras en Ajustes.")
    static func moduleOn(_ name: String) -> String { String(localized: "\(name) activado") }

    static let moduleMedia = tr("Medios"), moduleMediaDetail = tr("Qué suena y controles de reproducción")
    static let moduleShelf = tr("Estantería"), moduleShelfDetail = tr("Archivos a mano, temporales")
    static let moduleCalendar = tr("Calendario"), moduleCalendarDetail = tr("Tu próximo evento (pide permiso al usarlo)")
    static let moduleWidgets = tr("Widgets"), moduleWidgetsDetail = tr("Batería, temporizador y fecha")

    static let `continue` = tr("Continuar"), back = tr("Atrás"), skip = tr("Omitir"), start = tr("Empezar")
    static let close = tr("Cerrar"), done = tr("Hecho")
    static let skipHint = tr("Cierra la introducción sin cambiar nada")
}
