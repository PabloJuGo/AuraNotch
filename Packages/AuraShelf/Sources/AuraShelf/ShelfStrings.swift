import Foundation

/// Cadenas de la estantería (patrón de AuraDesignSystem.Strings: la clave es el texto en español).
enum ShelfStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let emptyTitle = tr("Estantería vacía")
    static let emptyMessage = tr("Arrastra archivos o enlaces aquí. Solo se guardan referencias: los originales no se mueven ni se borran.")
    static let add = tr("Añadir archivos…")
    static let addPrompt = tr("Añadir")
    static let open = tr("Abrir")
    static let reveal = tr("Mostrar en Finder")
    static let copyPath = tr("Copiar ruta")
    static let copyLink = tr("Copiar enlace")
    static let share = tr("Compartir…")
    static let airDrop = tr("AirDrop")
    static let airDropSend = tr("Enviar por AirDrop")
    static let airDropHint = tr("Suelta aquí archivos para enviarlos por AirDrop")
    static let airDropSelectionHint = tr("Envía la selección")
    static let airDropUnavailable = tr("AirDrop no disponible")
    static let airDropDrop = tr("Suelta para enviar")
    static let remove = tr("Quitar de la estantería")
    static let removeHint = tr("No borra el original")
    static let clear = tr("Limpiar estantería")
    static let selectAll = tr("Seleccionar todo")
    static let moveEarlier = tr("Mover antes")
    static let moveLater = tr("Mover después")
    static let recover = tr("Recuperar")
    static let missing = tr("Archivo no encontrado")
    static let missingHint = tr("Se movió, se borró o su volumen no está disponible")
    static let selected = tr("Seleccionado")
    static let dropHere = tr("Suelta para añadir")
    static let loadCorrupt = tr("No se pudo leer la estantería guardada. Se conservó una copia aparte y se empezó vacía.")
    static let loadNewer = tr("La estantería guardada es de una versión más nueva. Se conservó intacta y se empezó vacía.")
    static let dismiss = tr("Descartar")
    static let group = tr("Estantería")

    static func count(_ n: Int) -> String { n == 1 ? tr("1 elemento") : String(localized: "\(n) elementos") }
    static func selectedCount(_ n: Int) -> String { n == 1 ? tr("1 seleccionado") : String(localized: "\(n) seleccionados") }
    static func accepted(_ n: Int) -> String { n == 1 ? tr("1 añadido") : String(localized: "\(n) añadidos") }
}
