import Foundation

/// Cadenas de multimedia (la clave es el texto en español, como en AuraDesignSystem.Strings).
enum MediaStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let group = tr("Multimedia")
    static let loading = tr("Buscando reproductores…")
    static let noPlayerTitle = tr("Nada en reproducción")
    static let noPlayerMessage = tr("Reproduce algo en Música o Spotify y aparecerá aquí.")
    static let errorTitle = tr("Multimedia no disponible")
    static let errorCause = tr("No hay ningún proveedor multimedia configurado.")
    static let errorSolution = tr("Reinicia la app o revisa los módulos en Ajustes.")
    static let play = tr("Reproducir")
    static let pause = tr("Pausar")
    static let next = tr("Siguiente")
    static let previous = tr("Anterior")
    static let open = tr("Abrir reproductor")
    static let source = tr("Fuente")
    static let progress = tr("Progreso")
    static let allowControl = tr("Permitir control")
    static let authExplanation = tr("Para controlar la reproducción, macOS pedirá permiso de Automatización. Ver lo que suena no lo necesita.")
    static let authDenied = tr("El control está desactivado en Ajustes del Sistema > Privacidad > Automatización.")
    static let unknownTitle = tr("Sin título")

    static let errNotAuthorized = tr("Falta el permiso de Automatización para controlar este reproductor.")
    static let errDenied = tr("Automatización denegada. Actívala en Ajustes del Sistema > Privacidad y seguridad > Automatización.")
    static let errTimeout = tr("El reproductor no respondió a tiempo.")
    static let errNotRunning = tr("El reproductor no está abierto.")
    static func errFailed(_ m: String) -> String { m.isEmpty ? tr("No se pudo controlar el reproductor.") : String(localized: "No se pudo controlar el reproductor: \(m)") }

    static func sourceName(_ id: String) -> String {
        switch id {
        case "music": tr("Música")
        case "spotify": "Spotify"
        default: id
        }
    }
    static func playing(_ p: Bool) -> String { p ? tr("Reproduciendo") : tr("En pausa") }
    static func progressValue(_ pos: String, _ total: String) -> String { String(localized: "\(pos) de \(total)") }
}
