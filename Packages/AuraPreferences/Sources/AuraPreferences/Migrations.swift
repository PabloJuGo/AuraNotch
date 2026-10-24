import Foundation

/// Migraciones versionadas sobre el diccionario JSON (antes de decodificar).
enum SettingsMigration {
    /// Sube `dict` hasta la versión actual; `nil` si la versión es futura o inválida.
    static func migrate(_ dict: [String: Any]) -> [String: Any]? {
        var d = dict
        var v = (d["schemaVersion"] as? Int) ?? 0
        guard v >= 0, v <= AppSettings.currentSchemaVersion else { return nil }
        while v < AppSettings.currentSchemaVersion {
            switch v {
            case 0: d = v0toV1(d)
            default: return nil
            }
            v += 1
        }
        return d
    }

    /// v0 (prototipo): `hover`, `click`, `hoverDelayMs`, `startAtLogin`, `persistShelf`; sin versión.
    private static func v0toV1(_ old: [String: Any]) -> [String: Any] {
        var n: [String: Any] = ["schemaVersion": 1]
        if let b = old["startAtLogin"] as? Bool { n["launchAtLogin"] = b }
        if let b = old["hover"] as? Bool { n["openOnHover"] = b }
        if let b = old["click"] as? Bool { n["openOnClick"] = b }
        if let ms = old["hoverDelayMs"] as? NSNumber { n["hoverDelay"] = ms.doubleValue / 1000 }
        if let b = old["persistShelf"] as? Bool { n["persistShelf"] = b }
        return n
    }
}
