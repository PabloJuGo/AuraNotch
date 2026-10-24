import Foundation

/// Elemento de la estantería: una REFERENCIA (nunca una copia) a un archivo/carpeta o a una URL web.
///
/// Bookmarks normales (no security-scoped): la app no está en sandbox, así que
/// el acceso no depende de un permiso por archivo. Los scoped solo servirían bajo sandbox y añadirían
/// el deber de `start/stopAccessing` en cada acción; si se activa el sandbox, hay que migrar a scoped
/// (el formato guarda `bookmarkData` opaco, la migración sería regenerarlo al resolver).
public struct ShelfItem: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, web }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// Solo `.file`. Sobrevive a mover/renombrar el original dentro del volumen.
    public var bookmarkData: Data?
    /// Solo `.web`.
    public var webURL: URL?
    /// Última ruta conocida (solo `.file`): para copiar ruta y deduplicar si el archivo falta.
    public var lastKnownPath: String?
    public let addedAt: Date

    public init(id: UUID = UUID(), name: String, kind: Kind, bookmarkData: Data? = nil,
                webURL: URL? = nil, lastKnownPath: String? = nil, addedAt: Date = Date()) {
        self.id = id; self.name = name; self.kind = kind; self.bookmarkData = bookmarkData
        self.webURL = webURL; self.lastKnownPath = lastKnownPath; self.addedAt = addedAt
    }
}

/// Resultado de resolver la referencia.
public enum ShelfItemState: Equatable, Sendable {
    case available(URL)
    /// Borrado, en la Papelera, volumen desmontado o bookmark ilegible. Recuperable con `recover`.
    case missing
}

public struct ShelfAddResult: Equatable, Sendable {
    public var added: [ShelfItem] = []
    /// Ids de elementos ya existentes que coinciden con lo soltado.
    public var duplicates: [UUID] = []
    /// URLs no válidas (no existen, esquema no admitido).
    public var rejected: [URL] = []
    public init() {}
}

/// Estado del arrastre sobre la shelf (AN-06 / AN-07). El host lo lee para su highlight.
public enum ShelfDropState: Equatable, Sendable {
    case idle
    case targeted
    case accepted(count: Int)
}

public enum ShelfLoadIssue: Equatable, Sendable {
    /// Fichero ilegible: se conserva como `.corrupt` y se arranca vacío.
    case corrupt
    /// Esquema más nuevo que el soportado: se conserva y se arranca vacío.
    case newerSchema(Int)
}
