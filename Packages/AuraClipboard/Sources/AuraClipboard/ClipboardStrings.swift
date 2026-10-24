import Foundation

/// Cadenas del portapapeles (patrón de AuraDesignSystem.Strings: la clave es el texto en español).
enum ClipboardStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let group = tr("Portapapeles")
    static let emptyTitle = tr("Portapapeles vacío")
    static let emptyMessage = tr("Lo que copies (texto, enlaces e imágenes) aparecerá aquí. Solo se guarda en memoria.")
    static let text = tr("Texto")
    static let link = tr("Enlace")
    static let image = tr("Imagen")
    static let pin = tr("Fijar")
    static let unpin = tr("Desfijar")
    static let pinned = tr("Fijado")
    static let remove = tr("Borrar")
    static let clear = tr("Vaciar historial")
    static let copyHint = tr("Vuelve a copiarlo al portapapeles")

    static func count(_ n: Int) -> String { n == 1 ? tr("1 elemento") : String(localized: "\(n) elementos") }
}
