import AppKit
import AuraCore
import Foundation

// Extensiones ADITIVAS al contrato de AuraCore (que no se toca): solicitar permiso y abrir el origen.

public protocol MediaAuthorizing: MediaProvider {
    /// Muestra el diálogo de Automation. SOLO llamar tras pulsar un botón del usuario.
    func requestAuthorization() async throws -> AuthorizationState
}

public protocol MediaSourceOpenable: MediaProvider {
    func openSource() async -> Bool
}

/// Definición de un reproductor con script (Music, Spotify).
public struct PlayerSpec: Sendable {
    public let id: String, bundleID: String, notification: String
    /// Cómo expone la portada: bytes de la imagen (Música) o `artwork url` (Spotify).
    public let artworkIsURL: Bool
    public static let music = PlayerSpec(id: "music", bundleID: "com.apple.Music", notification: "com.apple.Music.playerInfo",
                                         artworkIsURL: false)
    public static let spotify = PlayerSpec(id: "spotify", bundleID: "com.spotify.client",
                                           notification: "com.spotify.client.PlaybackStateChanged", artworkIsURL: true)
}

/// Proveedor común. Metadatos por notificación (sin permiso); control por Apple Events solo con
/// Automation concedido. La portada también va por Apple Events, pero solo con el permiso ya concedido (`artworkLocation`).
/// Limitación: Music/Spotify solo notifican al CAMBIAR, así que al arrancar `currentItem` es nil hasta el
/// primer cambio de pista/estado.
public class ScriptablePlayerProvider: MediaProvider, MediaAuthorizing, MediaSourceOpenable, MediaArtworkSource, @unchecked Sendable {
    public let id: String
    let spec: PlayerSpec
    let feed: PlayerFeed
    let transport: AppleScriptTransport
    let permission: AutomationPermission
    let timeout: TimeInterval
    private let lock = NSLock()
    private var item: MediaItem?
    private var auth: AuthorizationState = .notDetermined
    private var queryInFlight = false
    /// Spotify no responde a la consulta silenciosa (ver `authorizationState`): recordar que el usuario ya concedió el permiso
    /// evita volver a pedírselo en cada arranque. Si se revoca, el primer comando falla y se borra.
    private let remembered: UserDefaults?
    private var rememberKey: String { "aura.media.automation-granted.\(spec.bundleID)" }

    init(spec: PlayerSpec, feed: PlayerFeed, transport: AppleScriptTransport, permission: AutomationPermission, timeout: TimeInterval,
         remembered: UserDefaults? = nil) {
        self.spec = spec; id = spec.id; self.feed = feed; self.transport = transport
        self.permission = permission; self.timeout = timeout; self.remembered = remembered
        if remembered?.bool(forKey: "aura.media.automation-granted.\(spec.bundleID)") == true { auth = .authorized }
    }

    private func setAuth(_ s: AuthorizationState) {
        locked { auth = s }
        remembered?.set(s == .authorized, forKey: rememberKey)
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    private var cachedAuth: AuthorizationState { locked { auth } }

    public var capabilities: MediaCapabilities {
        cachedAuth == .authorized ? [.openSource, .play, .pause, .skip, .seek] : [.openSource]
    }

    /// Consulta TCC sin diálogo. Si la app no está abierta no se puede saber: se conserva el último valor.
    /// VERIFICADO en macOS 27: `AEDeterminePermissionToAutomateTarget(askUser: false)` puede bloquearse
    /// >25 s, así que corre en un hilo aparte con timeout y nunca se apilan consultas pendientes.
    public var authorizationState: AuthorizationState {
        get async {
            let start = locked { () -> Bool in
                if queryInFlight { return false }
                queryInFlight = true; return true
            }
            guard start else { return cachedAuth }
            let status: AutomationStatus? = await withCheckedContinuation { cont in
                let gate = Once<AutomationStatus?>(cont)
                let (bundle, perm) = (spec.bundleID, permission)
                DispatchQueue.global(qos: .utility).async { [self] in
                    gate.resume(perm.status(bundleID: bundle, askUser: false))
                    locked { queryInFlight = false } // solo al terminar de verdad
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { gate.resume(nil) }
            }
            if let status, let s = Self.state(status) { setAuth(s) }
            return cachedAuth
        }
    }

    static func state(_ s: AutomationStatus) -> AuthorizationState? {
        switch s {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .targetNotRunning: nil
        }
    }

    public var currentItem: MediaItem? { get async { locked { item } } }

    /// `AEDeterminePermissionToAutomateTarget` no responde con Spotify en macOS 27 (medido: Finder y Música contestan al
    /// instante). Si no contesta en `askDeadline`, el permiso se pide enviando un Apple Event real e inocuo: macOS muestra
    /// su diálogo de Automation en el primer envío. Nunca se lanza una app cerrada.
    static let askDeadline: TimeInterval = 3

    public func requestAuthorization() async throws -> AuthorizationState {
        let (spec, permission) = (self.spec, self.permission)
        // Bloquea hasta que el usuario responde: fuera del MainActor y del pool cooperativo.
        let status: AutomationStatus? = await withCheckedContinuation { cont in
            let gate = Once<AutomationStatus?>(cont)
            DispatchQueue.global().async { gate.resume(permission.status(bundleID: spec.bundleID, askUser: true)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.askDeadline) { gate.resume(nil) }
        }
        if let status {
            guard let s = Self.state(status) else { throw MediaError.appNotRunning }
            setAuth(s)
            return s
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: spec.bundleID).isEmpty else { throw MediaError.appNotRunning }
        do {
            _ = try await transport.run("tell application id \"\(spec.bundleID)\" to return player state as string", timeout: 60)
            setAuth(.authorized)
            return .authorized
        } catch MediaError.permissionDenied {
            setAuth(.denied)
            return .denied
        }
    }

    public func play() async throws { try await command("play") }
    public func pause() async throws { try await command("pause") }
    public func skip(forward: Bool) async throws { try await command(forward ? "next track" : "previous track") }
    public func seek(to position: TimeInterval) async throws {
        guard position.isFinite else { throw MediaError.failed("") }
        try await command(String(format: "set player position to %.1f", max(0, position)))
    }

    private func command(_ verb: String) async throws {
        switch cachedAuth {
        case .authorized, .notRequired: break
        case .denied: throw MediaError.permissionDenied
        case .notDetermined: throw MediaError.notAuthorized
        }
        do {
            _ = try await transport.run("tell application id \"\(spec.bundleID)\" to \(verb)", timeout: timeout)
        } catch MediaError.permissionDenied {
            setAuth(.denied); throw MediaError.permissionDenied
        } catch let e as MediaError { throw e } catch { throw MediaError.failed(error.localizedDescription) }
    }

    /// Solo con Automation ya concedido (nunca pide permiso). `if ... is running` evita que el Apple Event relance
    /// el reproductor si se cerró justo después de la notificación.
    public func artworkLocation() async -> ArtworkLocation? {
        guard cachedAuth == .authorized else { return nil }
        let b = spec.bundleID
        func script(_ expr: String, orElse fallback: String) -> String {
            "if application id \"\(b)\" is running then\ntell application id \"\(b)\" to return \(expr)\nend if\nreturn \(fallback)"
        }
        do {
            if spec.artworkIsURL {
                let s = try await transport.run(script("artwork url of current track", orElse: "\"\""), timeout: timeout)
                return URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)).map(ArtworkLocation.remote)
            }
            let d = try await transport.runData(script("data of artwork 1 of current track", orElse: "missing value"), timeout: timeout)
            return d.isEmpty ? nil : .data(d)
        } catch { return nil }  // sin portada o sin respuesta: la vista conserva el placeholder
    }

    public func openSource() async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec.bundleID) else { return false }
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())) != nil
    }

    /// Estado al arrancar (OJO: `st` no compila como variable en AppleScript; solo con Automation concedido; `is running` evita relanzar el reproductor). Una sola línea por campo.
    func initialItem() async -> MediaItem? {
        guard cachedAuth == .authorized else { return nil }
        let b = spec.bundleID
        let source = """
        if application id "\(b)" is running then
        tell application id "\(b)"
        set theState to player state as string
        if theState is "stopped" then return ""
        set trk to current track
        return theState & linefeed & (name of trk) & linefeed & (artist of trk) & linefeed & ((duration of trk) as string) & linefeed & (player position as string)
        end tell
        end if
        return ""
        """
        guard let out = try? await transport.run(source, timeout: timeout) else { return nil }
        return Self.parseInitial(out, durationIsMilliseconds: spec.artworkIsURL)
    }

    /// `st, nombre, artista, duración, posición`. La duración de Spotify va en ms y la de Música en s; los decimales pueden traer coma.
    public static func parseInitial(_ out: String, durationIsMilliseconds: Bool) -> MediaItem? {
        let f = out.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard f.count >= 5 else { return nil }
        func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
        guard let d = num(f[3]), let pos = num(f[4]) else { return nil }
        let payload: [AnyHashable: Any] = ["Player State": f[0], "Name": f[1], "Artist": f[2],
                                           "Total Time": durationIsMilliseconds ? d : d * 1000, "Playback Position": pos]
        if case .item(let item) = PlayerPayload.parse(payload) { return item }
        return nil
    }

    public func observe() -> AsyncStream<MediaItem?> {
        let upstream = feed.events(notification: spec.notification, bundleID: spec.bundleID)
        return AsyncStream { cont in
            let task = Task { [weak self] in
                // Spotify/Música solo notifican al cambiar: con el permiso ya concedido se lee el estado actual una vez.
                if let first = await self?.initialItem() {
                    self?.locked { self?.item = first }
                    cont.yield(first)
                }
                for await value in upstream {
                    self?.locked { self?.item = value }
                    cont.yield(value)
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

public final class MusicProvider: ScriptablePlayerProvider, @unchecked Sendable {
    public init(feed: PlayerFeed = DistributedPlayerFeed(), transport: AppleScriptTransport = NSAppleScriptTransport(),
                permission: AutomationPermission = SystemAutomationPermission(), timeout: TimeInterval = 5,
                remembered: UserDefaults? = nil) {
        super.init(spec: .music, feed: feed, transport: transport, permission: permission, timeout: timeout, remembered: remembered)
    }
}

/// Misma estructura que Music; el formato de claves de Spotify está igualmente por verificar.
public final class SpotifyProvider: ScriptablePlayerProvider, @unchecked Sendable {
    public init(feed: PlayerFeed = DistributedPlayerFeed(), transport: AppleScriptTransport = NSAppleScriptTransport(),
                permission: AutomationPermission = SystemAutomationPermission(), timeout: TimeInterval = 5,
                remembered: UserDefaults? = nil) {
        super.init(spec: .spotify, feed: feed, transport: transport, permission: permission, timeout: timeout, remembered: remembered)
    }
}

/// Reanuda una continuación una sola vez (resultado vs. timeout).
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?
    init(_ c: CheckedContinuation<T, Never>) { cont = c }
    func resume(_ r: T) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: r)
    }
}
