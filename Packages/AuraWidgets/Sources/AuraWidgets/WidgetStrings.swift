import Foundation

/// Cadenas de widgets (la clave es el texto en español, como en AuraDesignSystem.Strings).
enum WidgetStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let group = tr("Widgets")
    static let loading = tr("Cargando…")
    static let disabled = tr("Desactivado")
    static let unavailable = tr("No disponible en este Mac")
    static let enable = tr("Activar")
    static let disable = tr("Desactivar")
    static let moveEarlier = tr("Mover antes")
    static let moveLater = tr("Mover después")
    static func options(_ name: String) -> String { String(localized: "Opciones de \(name)") }
    static let noWidgetsTitle = tr("Sin widgets")
    static let noWidgetsMessage = tr("Activa alguno en los ajustes del módulo.")

    // Temporizador
    static let timerName = tr("Temporizador")
    static let start = tr("Iniciar")
    static let pause = tr("Pausar")
    static let resume = tr("Reanudar")
    static let cancel = tr("Cancelar")
    static let restart = tr("Reiniciar")
    static let dismiss = tr("Cerrar")
    static let finished = tr("Terminado")
    static let finishedTitle = tr("Temporizador terminado")
    static func finishedBody(_ spoken: String) -> String { String(localized: "Ha terminado el temporizador de \(spoken).") }
    static let lessTime = tr("Menos tiempo")
    static let moreTime = tr("Más tiempo")
    static let remainingLabel = tr("Tiempo restante")
    static let durationLabel = tr("Duración")
    static func minutes(_ m: Int) -> String { String(localized: "\(m) min") }
    static func spoken(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full; f.allowedUnits = [.hour, .minute, .second]
        return f.string(from: max(0, seconds.rounded(.up))) ?? "\(Int(seconds)) s"
    }
    static func timerSummary(_ phase: String, _ time: String) -> String { String(localized: "\(phase): \(time)") }
    static let idle = tr("Preparado")
    static let running = tr("En marcha")
    static let paused = tr("En pausa")

    // Batería
    static let batteryName = tr("Batería")
    static let noBatteryMessage = tr("Este Mac no tiene batería.")
    static let batteryErrorCause = tr("No se pudo leer el estado de energía.")
    static let batteryErrorSolution = tr("Pulsa Reintentar; si persiste, reinicia la app.")
    static let charging = tr("Cargando")
    static let pluggedIn = tr("Conectado a corriente")
    static let charged = tr("Carga completa")
    static let onBattery = tr("Con batería")
    static let lowPower = tr("Modo de bajo consumo")
    static let low = tr("Batería baja")
    static func percent(_ p: Int) -> String { String(localized: "\(p) %") }
    static func timeLeft(_ minutes: Int) -> String { String(localized: "\(spokenMinutes(minutes)) restantes") }
    static func timeToFull(_ minutes: Int) -> String { String(localized: "\(spokenMinutes(minutes)) para completar") }
    static func spokenMinutes(_ m: Int) -> String {
        m >= 60 ? (m % 60 == 0 ? String(localized: "\(m / 60) h") : String(localized: "\(m / 60) h \(m % 60) min")) : String(localized: "\(m) min")
    }

    // Volumen
    static let volumeName = tr("Volumen")
    static let volumeLabel = tr("Nivel de volumen")
    static let volumeNoControl = tr("Esta salida de audio no permite ajustar el volumen desde el Mac.")
    static let volumeErrorCause = tr("No se pudo leer el volumen del sistema.")
    static let volumeErrorSolution = tr("Pulsa Reintentar; comprueba que haya una salida de audio.")
    static let muted = tr("Silenciado")
    static let mute = tr("Silenciar")
    static let unmute = tr("Activar sonido")

    // Fecha
    static let dateName = tr("Fecha")

    // Acciones
    static let actionsName = tr("Acciones")
    static let noActionsMessage = tr("Elige acciones favoritas en los ajustes.")
    static let openSettings = tr("Abrir Ajustes del Sistema")
    static let openDownloads = tr("Abrir Descargas")
    static let copyDate = tr("Copiar fecha")
    static let actionFailed = tr("No se pudo completar la acción.")
    static let done = tr("Hecho")
}
