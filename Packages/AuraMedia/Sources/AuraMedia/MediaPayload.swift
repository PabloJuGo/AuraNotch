import AuraCore
import Foundation

/// Resultado de interpretar una notificación de reproductor.
public enum PayloadResult: Equatable, Sendable {
    case item(MediaItem)
    /// Reproductor detenido: no hay fuente (limpiar metadatos).
    case stopped
    /// Carga ilegible o incompleta: se ignora (NO borra lo que ya se muestra).
    case invalid
}

/// Parseo de `com.apple.Music.playerInfo` y `com.spotify.client.PlaybackStateChanged`.
///
/// POR VERIFICAR con reproducción real: las claves salen de documentación/observaciones de terceros
/// (Name, Artist, Album, "Total Time" en ms [Music], "Duration" en ms y "Playback Position" en s
/// [Spotify], "Player State" = Playing/Paused/Stopped). El parseo es tolerante: acepta números como
/// NSNumber/Int/Double/String y descarta lo ilegible en vez de fallar.
public enum PlayerPayload {
    static let maxTextLength = 200

    public static func parse(_ info: [AnyHashable: Any]) -> PayloadResult {
        guard let state = (info["Player State"] as? String)?.lowercased() else { return .invalid }
        switch state {
        case "stopped": return .stopped
        case "playing", "paused": break
        default: return .invalid
        }
        guard let title = clean(info["Name"] as? String) else { return .invalid }
        let ms = number(info["Total Time"]) ?? number(info["Duration"])
        let duration = ms.flatMap { $0 > 0 ? $0 / 1000 : nil }
        let position = number(info["Playback Position"]).flatMap { $0 >= 0 ? $0 : nil }
        return .item(MediaItem(title: title, artist: clean(info["Artist"] as? String), duration: duration,
                               position: position, isPlaying: state == "playing"))
    }

    /// Quita caracteres de control, recorta y limita longitud; vacío -> nil.
    static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let scalars = s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) }
        let t = String(scalars).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : String(t.prefix(maxTextLength))
    }

    static func number(_ v: Any?) -> Double? {
        let d: Double?
        switch v {
        case let n as NSNumber: d = n.doubleValue
        case let s as String: d = Double(s)
        default: d = nil
        }
        return d.flatMap { $0.isFinite ? $0 : nil }
    }
}
