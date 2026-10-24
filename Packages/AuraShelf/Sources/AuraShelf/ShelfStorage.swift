import Foundation

/// Formato en disco: `{ "schemaVersion": 1, "items": [...] }`. Subir `currentVersion` al cambiar el
/// formato y añadir el caso de migración en `load`.
enum ShelfStorage {
    static let currentVersion = 1

    private struct Envelope: Codable { var schemaVersion: Int; var items: [ShelfItem] }
    private struct VersionOnly: Decodable { var schemaVersion: Int }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraNotch", isDirectory: true).appendingPathComponent("shelf.json")
    }

    static func encode(_ items: [ShelfItem]) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try? e.encode(Envelope(schemaVersion: currentVersion, items: items))
    }

    /// Nunca lanza: fichero ausente = vacío; corrupto o de versión futura = vacío + aviso, y el original
    /// se aparta a `.corrupt` para no perderlo ni pisarlo.
    static func load(_ url: URL) -> (items: [ShelfItem], issue: ShelfLoadIssue?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], nil) }
        guard let data = try? Data(contentsOf: url) else { return ([], quarantine(url, .corrupt)) }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let v = try? d.decode(VersionOnly.self, from: data) else { return ([], quarantine(url, .corrupt)) }
        guard v.schemaVersion <= currentVersion else { return ([], quarantine(url, .newerSchema(v.schemaVersion))) }
        switch v.schemaVersion {
        case 1:
            if let e = try? d.decode(Envelope.self, from: data) { return (e.items, nil) }
            return ([], quarantine(url, .corrupt))
        default: return ([], quarantine(url, .corrupt))
        }
    }

    private static func quarantine(_ url: URL, _ issue: ShelfLoadIssue) -> ShelfLoadIssue {
        let dest = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: url, to: dest)
        return issue
    }
}

/// Escritor fuera del MainActor. `seq` creciente: una escritura antigua que llega tarde se descarta.
actor ShelfWriter {
    private var last = 0

    func write(_ data: Data, to url: URL, seq: Int) -> String? {
        guard seq > last else { return nil }
        last = seq
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return nil
        } catch { return error.localizedDescription }
    }

    func erase(_ url: URL, seq: Int) {
        guard seq > last else { return }
        last = seq
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
    }
}
