import Foundation

enum HomeStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let summary = tr("Resumen de Inicio")
    static let loading = tr("Cargando…")
    static let morning = tr("Buenos días"), afternoon = tr("Buenas tardes"), evening = tr("Buenas noches")
    static let quiet = tr("Todo en calma")

    // Temporizador
    static let timer = tr("Temporizador")
    static let timerPaused = tr("En pausa"), timerRunning = tr("En marcha"), timerDone = tr("Terminado")
    static let pause = tr("Pausar"), resume = tr("Reanudar"), cancelTimer = tr("Cancelar temporizador"), dismiss = tr("Descartar")
    // Medios
    static let nowPlaying = tr("Suena ahora"), mediaPaused = tr("En pausa")
    static let play = tr("Reproducir"), previous = tr("Anterior"), next = tr("Siguiente")
    // Calendario
    static let nextEvent = tr("Próximo evento"), today = tr("Hoy")
    static let noEventsToday = tr("Sin eventos hoy"), calendarNeedsAccess = tr("Da acceso al calendario para ver tus eventos")
    static let calendarLoading = tr("Cargando…"), calendarError = tr("No se pudo leer el calendario")
    static let clipboardEmpty = tr("Lo que copies aparecerá aquí"), shelfEmpty = tr("Suelta archivos aquí para tenerlos a mano")
    // Portapapeles
    static let clipboard = tr("Portapapeles"), clipboardCopyHint = tr("Vuelve a copiarlo")
    static func clipboardImage() -> String { tr("Imagen") }
    // Estantería
    static let shelf = tr("Estantería")
    // Estantería
    static func shelfCount(_ n: Int) -> String { n == 1 ? tr("1 elemento en la estantería") : String(localized: "\(n) elementos en la estantería") }
    // Batería
    static let battery = tr("Batería"), lowBattery = tr("Batería baja"), charging = tr("Cargando")
    static func percent(_ p: Int) -> String { String(localized: "\(p) %") }

    static func hint(_ module: String) -> String { String(localized: "Abre \(module)") }
    static func timerSpoken(_ clock: String) -> String { String(localized: "quedan \(clock)") }
}
