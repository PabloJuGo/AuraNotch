import AppKit
import AuraCore
import Foundation

// Todo lo que toca Apple Events / TCC vive detrás de estos protocolos para poder inyectar falsos.

/// Errores legibles de control (mensajes en español para la UI).
public enum MediaError: Error, Equatable, LocalizedError, Sendable {
    case notAuthorized, permissionDenied, timeout, appNotRunning, failed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: MediaStrings.errNotAuthorized
        case .permissionDenied: MediaStrings.errDenied
        case .timeout: MediaStrings.errTimeout
        case .appNotRunning: MediaStrings.errNotRunning
        case .failed(let m): MediaStrings.errFailed(m)
        }
    }
}

/// Envío de un script de Apple Events. Implementaciones: con timeout propio y fuera del MainActor.
public protocol AppleScriptTransport: Sendable {
    func run(_ source: String, timeout: TimeInterval) async throws -> String
    /// Como `run`, pero devuelve los bytes del resultado (p. ej. `data of artwork`). Vacío = sin resultado.
    func runData(_ source: String, timeout: TimeInterval) async throws -> Data
}

extension AppleScriptTransport {
    public func runData(_ source: String, timeout: TimeInterval) async throws -> Data { throw MediaError.failed("") }
}

/// Estado de Automation para una app destino.
public enum AutomationStatus: Equatable, Sendable { case authorized, denied, notDetermined, targetNotRunning }

/// Consulta/solicitud de permiso de Automation. `askUser == false` NO debe mostrar diálogo.
public protocol AutomationPermission: Sendable {
    /// Síncrono; con `askUser == true` puede bloquear hasta que el usuario responda: llamar fuera del MainActor.
    func status(bundleID: String, askUser: Bool) -> AutomationStatus
}

/// `AEDeterminePermissionToAutomateTarget` (público, macOS 10.14+). Con askUserIfNeeded=false solo
/// consulta TCC; no envía ningún Apple Event. Requiere que la app destino esté en ejecución (-600 si no).
/// Compila y está documentado así, PERO no se ha ejecutado contra apps reales en esta fase.
public struct SystemAutomationPermission: AutomationPermission {
    public init() {}
    public func status(bundleID: String, askUser: Bool) -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notDetermined }
        let code = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, askUser)
        switch code {
        case noErr: return .authorized
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .notDetermined  // incluye errAEEventWouldRequireUserConsent (-1744)
        }
    }
}

/// Corta una continuación para que se reanude una sola vez (script terminado vs. timeout).
private final class OnceGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { cont = c }
    func resume(_ r: Result<T, Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(with: r)
    }
}

/// Transporte real con NSAppleScript. Cola serie propia (NSAppleScript no es thread-safe) y
/// `with timeout` en el script + carrera con un temporizador externo. Solo se invoca tras acción del usuario.
public final class NSAppleScriptTransport: AppleScriptTransport {
    private let queue = DispatchQueue(label: "aura.media.applescript")
    public init() {}

    public func run(_ source: String, timeout: TimeInterval) async throws -> String {
        try await execute(source, timeout: timeout) { $0?.stringValue ?? "" }
    }

    public func runData(_ source: String, timeout: TimeInterval) async throws -> Data {
        try await execute(source, timeout: timeout) { $0?.data ?? Data() }
    }

    private func execute<T: Sendable>(_ source: String, timeout: TimeInterval,
                                      _ extract: @escaping @Sendable (NSAppleEventDescriptor?) -> T) async throws -> T {
        let secs = max(1, Int(timeout.rounded(.up)))
        let wrapped = "with timeout of \(secs) seconds\n\(source)\nend timeout"
        return try await withCheckedThrowingContinuation { cont in
            let gate = OnceGate<T>(cont)
            queue.async {
                var info: NSDictionary?
                let result = NSAppleScript(source: wrapped)?.executeAndReturnError(&info)
                if let info {
                    gate.resume(.failure(Self.map(info)))
                } else {
                    gate.resume(.success(extract(result)))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(secs) + 1) { gate.resume(.failure(MediaError.timeout)) }
        }
    }

    static func map(_ info: NSDictionary) -> MediaError {
        switch info[NSAppleScript.errorNumber] as? Int {
        case .some(-1743): .permissionDenied
        case .some(-1744): .notAuthorized
        case .some(-1712): .timeout
        case .some(-600), .some(-609): .appNotRunning
        default: .failed((info[NSAppleScript.errorMessage] as? String) ?? "")
        }
    }
}
