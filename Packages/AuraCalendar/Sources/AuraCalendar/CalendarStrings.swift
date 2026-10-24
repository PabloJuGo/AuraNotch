import Foundation

enum CalendarStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let group = tr("Calendario")
    static let loading = tr("Cargando eventos…")
    static let header = tr("Próximos eventos")
    static let emptyTitle = tr("Sin eventos próximos")
    static func emptyMessage(days: Int) -> String { String(localized: "No tienes eventos en los próximos \(days) días.") }
    static let askTitle = tr("Calendario")
    static let askMessage = tr("Aura Notch leerá tus eventos solo para mostrarlos aquí. No los modifica ni guarda copias.")
    static let allow = tr("Permitir acceso")
    static let waiting = tr("Esperando respuesta de macOS…")
    static let timeoutNotice = tr("macOS no ha respondido todavía. Si ves un diálogo, contéstalo; si no, vuelve a intentarlo.")
    static let deniedTitle = tr("Acceso al calendario denegado")
    static let deniedMessage = tr("Actívalo en Ajustes del Sistema > Privacidad y seguridad > Calendarios para ver tus próximos eventos.")
    static let restrictedTitle = tr("Calendario no disponible")
    static let restrictedMessage = tr("El sistema solo permite escribir eventos o restringe el acceso. Cambia el permiso a «Acceso completo» en Ajustes del Sistema > Calendarios.")
    static let errorTitle = tr("No se pudieron cargar los eventos")
    static let errorSolution = tr("Reintenta; si persiste, revisa el permiso en Ajustes del Sistema.")
    static let denialFallback = tr("Acceso denegado.")
    static let openHint = tr("Abre Calendario")
    static let untitled = tr("Sin título")
    static let unnamedCalendar = tr("Calendario sin nombre")
    static let allDay = tr("todo el día")
    static let today = tr("hoy"), tomorrow = tr("mañana"), yesterday = tr("ayer")

    static func timed(day: String, from: String, to: String) -> String { String(localized: "\(day) de \(from) a \(to)") }
    static func timedCrossing(day: String, from: String, endDay: String, to: String) -> String {
        String(localized: "\(day) desde las \(from) hasta \(endDay) a las \(to)")
    }
    static func allDay(day: String) -> String { String(localized: "\(day), todo el día") }
    static func allDayRange(from: String, to: String) -> String { String(localized: "del \(from) al \(to), todo el día") }
    static func spoken(title: String, when: String, calendar: String) -> String {
        String(localized: "\(title), \(when), calendario \(calendar)")
    }
    static func inMinutes(_ title: String, _ m: Int) -> String { String(localized: "\(title) en \(m) min") }
    static func startsInMinutes(_ title: String, _ m: Int) -> String { String(localized: "\(title) empieza en \(m) minutos") }
}
