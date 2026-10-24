import AuraCore
import Foundation
import Observation

public enum MediaState: Equatable, Sendable {
    case loading, noPlayer, ready
    case error(String)
}

/// Lo que la UI muestra. `item.position` va siempre a nil: el progreso vive fuera de lo observable.
public struct MediaSnapshot: Equatable, Sendable {
    public var providerID: String
    public var item: MediaItem
    public var capabilities: MediaCapabilities
    public var authorization: AuthorizationState
}

public struct SourceCandidate: Equatable, Sendable {
    public var id: String, isPlaying: Bool, activity: UInt64
    public init(id: String, isPlaying: Bool, activity: UInt64) { self.id = id; self.isPlaying = isPlaying; self.activity = activity }
}

/// Política de prioridad: selección manual (si esa fuente tiene algo) > la que reproduce
/// (la de actividad más reciente si hay varias) > la de actividad más reciente.
public enum MediaPriority {
    public static func choose(_ c: [SourceCandidate], manual: String?) -> String? {
        if let manual, c.contains(where: { $0.id == manual }) { return manual }
        let pool = c.contains(where: \.isPlaying) ? c.filter(\.isPlaying) : c
        return pool.max { $0.activity < $1.activity }?.id
    }
}

/// Controles visibles según capacidades (nunca se muestra uno que el proveedor no declare).
public struct MediaControls: Equatable, Sendable {
    public var previous, playPause, next, seek, open: Bool
    public init(_ caps: MediaCapabilities, isPlaying: Bool) {
        previous = caps.contains(.skip)
        next = caps.contains(.skip)
        playPause = caps.contains(isPlaying ? .pause : .play)
        seek = caps.contains(.seek)
        open = caps.contains(.openSource)
    }
}

public struct MediaCompactInfo: Equatable, Sendable {
    public var activity: ActivityKind
    public var detail: String
    public var accessibilityLabel: String
}

@MainActor @Observable
public final class MediaService {
    public private(set) var state: MediaState = .loading
    public private(set) var current: MediaSnapshot?
    /// Fuentes con algo cargado (para el selector manual).
    public private(set) var sources: [String] = []
    public private(set) var selectedSourceID: String?
    public private(set) var actionError: String?
    /// Sube solo cuando el progreso salta (seek externo) con el resto igual: fuerza un redibujado puntual.
    public private(set) var positionEpoch = 0
    /// Nº de veces que cambió algo observable (las pruebas lo usan para verificar la coalescencia).
    @ObservationIgnored public private(set) var renderRevision = 0

    private struct Entry {
        var item: MediaItem?
        var activity: UInt64 = 0
        var capabilities: MediaCapabilities = []
        var authorization: AuthorizationState = .notDetermined
        var anchor: (position: TimeInterval, date: Date, playing: Bool)?
        /// Ya se intentó la portada de esta pista (un fallo no se reintenta en bucle).
        var artworkRequested = false
    }
    @ObservationIgnored private let providers: [any MediaProvider]
    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var pendingInit = 0
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let artworkLoader: any ArtworkDataLoader
    @ObservationIgnored private var artworkTasks: [String: Task<Void, Never>] = [:]
    /// Caché en memoria por URL (ya reducidas); acotada, la más antigua sale primero.
    @ObservationIgnored private var artworkCache: [(url: URL, data: Data)] = []
    private static let artworkCacheLimit = 8

    /// Permite descargar portadas de una URL (Spotify). AppCoordinator lo sincroniza con `loadSpotifyArtwork`.
    @ObservationIgnored public var loadsRemoteArtwork = true {
        didSet {
            guard loadsRemoteArtwork != oldValue else { return }
            if !loadsRemoteArtwork { cancelArtwork() }
            for id in entries.keys { entries[id]?.artworkRequested = false; fetchArtwork(id) }
        }
    }

    public init(providers: [any MediaProvider], now: @escaping () -> Date = Date.init,
                artworkLoader: any ArtworkDataLoader = URLSessionArtworkLoader()) {
        self.providers = providers; self.now = now; self.artworkLoader = artworkLoader
        for p in providers { entries[p.id] = Entry() }
    }

    // MARK: Ciclo de vida

    public func start() {
        stop()
        guard !providers.isEmpty else { set(&state, .error(MediaStrings.errorCause)); return }
        // Arrancar solo escucha notificaciones: la consulta de permiso (puede bloquearse, ver API_CAPABILITIES)
        // se hace al mostrar la vista (`refreshAuthorization`), no al iniciar la app.
        pendingInit = 0
        recompute()
        for p in providers {
            tasks.append(Task { [weak self] in
                for await item in p.observe() {
                    if Task.isCancelled { break }
                    self?.apply(item, from: p.id)
                }
            })
        }
    }

    /// Consulta el estado de Automation de cada proveedor (sin diálogo). Llamar al mostrar el módulo.
    public func refreshAuthorization() async { for p in providers { await refresh(p) } }

    public func stop() { tasks.forEach { $0.cancel() }; tasks = []; cancelArtwork() }

    private func cancelArtwork() {
        artworkTasks.values.forEach { $0.cancel() }
        artworkTasks = [:]
        for id in entries.keys { entries[id]?.artworkRequested = false }
    }

    private func initDone() { pendingInit = max(0, pendingInit - 1); recompute() }

    private func refresh(_ p: any MediaProvider) async {
        let auth = await p.authorizationState
        entries[p.id]?.authorization = auth
        entries[p.id]?.capabilities = p.capabilities
        recompute()
        fetchArtwork(p.id)  // el permiso pudo llegar después de la pista
    }

    // MARK: Portada

    private func sameTrack(_ a: MediaItem, _ b: MediaItem) -> Bool { a.title == b.title && a.artist == b.artist && a.duration == b.duration }

    /// Pide la portada de la pista actual de `id` (una vez por pista). Cancelable: cambiar de pista cancela la anterior.
    private func fetchArtwork(_ id: String) {
        guard let e = entries[id], let item = e.item, item.artworkData == nil, !e.artworkRequested,
              e.authorization == .authorized, let source = providers.first(where: { $0.id == id }) as? MediaArtworkSource else { return }
        entries[id]?.artworkRequested = true
        artworkTasks[id]?.cancel()
        artworkTasks[id] = Task { [weak self] in
            guard let data = await self?.loadArtwork(from: source), !Task.isCancelled, let self,
                  var e = self.entries[id], var cur = e.item, self.sameTrack(cur, item) else { return }
            cur.artworkData = data
            e.item = cur; self.entries[id] = e
            self.recompute()
        }
    }

    private func loadArtwork(from source: MediaArtworkSource) async -> Data? {
        switch await source.artworkLocation() {
        case .data(let d): return await Self.shrink(d)
        case .remote(let url):
            guard loadsRemoteArtwork, url.scheme == "https" else { return nil }
            if let hit = artworkCache.first(where: { $0.url == url }) { return hit.data }
            guard let raw = try? await artworkLoader.data(from: url), let small = await Self.shrink(raw) else { return nil }
            artworkCache.append((url, small))
            if artworkCache.count > Self.artworkCacheLimit { artworkCache.removeFirst() }
            return small
        case nil: return nil
        }
    }

    private nonisolated static func shrink(_ d: Data) async -> Data? { ArtworkImage.thumbnail(d) }

    // MARK: Entrada de eventos

    func apply(_ incoming: MediaItem?, from id: String) {
        guard var e = entries[id] else { return }
        sequence += 1
        guard var item = incoming else {  // fuente perdida: limpiar metadatos y progreso
            e.item = nil; e.anchor = nil; e.artworkRequested = false; entries[id] = e
            artworkTasks[id]?.cancel(); artworkTasks[id] = nil
            recompute(); return
        }
        let pos = item.position
        item.position = nil
        if let old = e.item, sameTrack(old, item) {
            item.artworkData = item.artworkData ?? old.artworkData  // pausa/reanudar no tira la portada
        } else {
            e.artworkRequested = false; artworkTasks[id]?.cancel(); artworkTasks[id] = nil
        }
        let sameDisplay = e.item == item
        if let pos {
            // Un salto > 2 s respecto a lo interpolado es un seek; el resto es deriva y no redibuja.
            let expected = position(of: e, at: now())
            if sameDisplay, expected == nil || abs(expected! - pos) > 2 { positionEpoch += 1; renderRevision += 1 }
            e.anchor = (pos, now(), item.isPlaying)
        } else if !sameDisplay {
            e.anchor = nil  // pista nueva sin posición conocida: no se inventa
        }
        e.item = item
        if !sameDisplay || e.activity == 0 { e.activity = sequence }
        entries[id] = e
        recompute()
        fetchArtwork(id)
    }

    private func recompute() {
        let cands = entries.compactMap { id, e in e.item.map { SourceCandidate(id: id, isPlaying: $0.isPlaying, activity: e.activity) } }
        let chosen = MediaPriority.choose(cands, manual: selectedSourceID)
        let snap = chosen.flatMap { id in entries[id].flatMap { e in e.item.map {
            MediaSnapshot(providerID: id, item: $0, capabilities: e.capabilities, authorization: e.authorization) } } }
        set(&current, snap)
        set(&sources, cands.map(\.id).sorted())
        if case .error = state, providers.isEmpty { return }
        set(&state, snap != nil ? .ready : (pendingInit > 0 ? .loading : .noPlayer))
    }

    private func set<T: Equatable>(_ keyPath: inout T, _ value: T) {
        guard keyPath != value else { return }
        keyPath = value; renderRevision += 1
    }

    // MARK: Progreso (fuera de lo observable)

    private func position(of e: Entry, at date: Date) -> TimeInterval? {
        guard let a = e.anchor else { return nil }
        let p = a.position + (a.playing ? max(0, date.timeIntervalSince(a.date)) : 0)
        return min(max(0, p), e.item?.duration ?? p)
    }

    /// Posición interpolada de la fuente mostrada; nil si el proveedor no la da.
    public func position(at date: Date) -> TimeInterval? {
        guard let id = current?.providerID, let e = entries[id] else { return nil }
        return position(of: e, at: date)
    }

    // MARK: Acciones (todas explícitas del usuario)

    public func selectSource(_ id: String?) { selectedSourceID = id; recompute() }

    public func togglePlayPause() async {
        guard let c = current else { return }
        await perform(c.providerID) { c.item.isPlaying ? try await $0.pause() : try await $0.play() }
    }

    public func skip(forward: Bool) async {
        guard let c = current else { return }
        await perform(c.providerID) { try await $0.skip(forward: forward) }
    }

    public func seek(to position: TimeInterval) async {
        guard let c = current else { return }
        await perform(c.providerID) { try await $0.seek(to: position) }
    }

    /// Para VoiceOver (ajustable): ±delta sobre la posición interpolada.
    public func seek(by delta: TimeInterval) async {
        guard let p = position(at: now()) else { return }
        await seek(to: max(0, p + delta))
    }

    public func openSource() async {
        guard let id = current?.providerID, let p = providers.first(where: { $0.id == id }) as? MediaSourceOpenable else { return }
        _ = await p.openSource()
    }

    /// Dispara el diálogo de Automation. Llamar solo desde el botón «Permitir control».
    public func requestAuthorization() async {
        guard let id = current?.providerID, let p = providers.first(where: { $0.id == id }) else { return }
        await perform(id) { _ in
            guard let a = p as? MediaAuthorizing else { return }
            _ = try await a.requestAuthorization()
        }
    }

    private func perform(_ id: String, _ op: (any MediaProvider) async throws -> Void) async {
        guard let p = providers.first(where: { $0.id == id }) else { return }
        do { try await op(p); set(&actionError, nil) } catch {
            set(&actionError, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        await refresh(p)
    }

    // MARK: Compacto

    /// Para alimentar `ActivityKind.media(playing:)` y `CompactContent(detail:)`; nil = sin actividad.
    public var compactInfo: MediaCompactInfo? {
        guard let c = current else { return nil }
        let title = c.item.title // la vista lo recorta por ancho (el ala solo da para ~16 caracteres)
        return MediaCompactInfo(activity: .media(playing: c.item.isPlaying), detail: title,
                                accessibilityLabel: "\(MediaStrings.playing(c.item.isPlaying)): \(c.item.title)")
    }
}
