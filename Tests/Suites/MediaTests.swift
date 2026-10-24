import AppKit
import AuraCore
import AuraMedia
import SwiftUI

/// Suite de AuraMedia (AURA-013/014). Sin Apple Events reales: transporte y permiso son falsos.
/// Con `AURA_MEDIA_RENDER_DIR=<ruta>` además genera PNG (NSHostingView en ventana fuera de pantalla).
/// La única parte «real» es DistributedNotificationCenter con una notificación sintética propia.

// MARK: - Dobles

private final class FakeProvider: MediaProvider, MediaAuthorizing, MediaArtworkSource, @unchecked Sendable {
    var artwork: ArtworkLocation?
    func artworkLocation() async -> ArtworkLocation? { artwork }
    let id: String
    var capabilities: MediaCapabilities
    var auth: AuthorizationState
    var calls: [String] = []
    var failure: MediaError?
    private var cont: AsyncStream<MediaItem?>.Continuation?
    init(_ id: String, caps: MediaCapabilities = [.play, .pause, .skip, .openSource], auth: AuthorizationState = .authorized) {
        self.id = id; capabilities = caps; self.auth = auth
    }
    var authorizationState: AuthorizationState { get async { auth } }
    var currentItem: MediaItem? { get async { nil } }
    private func rec(_ s: String) throws { calls.append(s); if let failure { throw failure } }
    func play() async throws { try rec("play") }
    func pause() async throws { try rec("pause") }
    func skip(forward: Bool) async throws { try rec(forward ? "next" : "prev") }
    func seek(to p: TimeInterval) async throws { try rec("seek \(p)") }
    func requestAuthorization() async throws -> AuthorizationState { calls.append("auth"); auth = .authorized; capabilities = [.play, .pause, .skip, .seek, .openSource]; return .authorized }
    func observe() -> AsyncStream<MediaItem?> { AsyncStream { self.cont = $0 } }
    func send(_ i: MediaItem?) { cont?.yield(i) }
}

private final class FakeTransport: AppleScriptTransport, @unchecked Sendable {
    var scripts: [String] = []
    var result: Result<String, MediaError> = .success("")
    var data = Data()
    func run(_ source: String, timeout: TimeInterval) async throws -> String { scripts.append(source); return try result.get() }
    func runData(_ source: String, timeout: TimeInterval) async throws -> Data { scripts.append(source); _ = try result.get(); return data }
}

private struct FakePermission: AutomationPermission {
    var status: AutomationStatus
    func status(bundleID: String, askUser: Bool) -> AutomationStatus { status }
}

/// Simula el bloqueo real observado de `AEDeterminePermissionToAutomateTarget` en macOS 27.
private final class HangingPermission: AutomationPermission, @unchecked Sendable {
    private let lock = NSLock(); private var calls = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func status(bundleID: String, askUser: Bool) -> AutomationStatus {
        lock.lock(); calls += 1; lock.unlock()
        Thread.sleep(forTimeInterval: 4)
        return .authorized
    }
}

private struct FakeFeed: PlayerFeed {
    func events(notification: String, bundleID: String) -> AsyncStream<MediaItem?> { AsyncStream { $0.finish() } }
}

@MainActor private func pump(_ seconds: Double = 0.1, until cond: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func song(_ title: String = "Canción", playing: Bool = true, pos: TimeInterval? = nil) -> MediaItem {
    MediaItem(title: title, artist: "Artista", duration: 200, position: pos, isPlaying: playing)
}

// MARK: - Suite

@MainActor
func runMediaSuite(_ t: SelfCheck) {
    parsing(t)
    priority(t)
    controls(t)
    providerBehavior(t)
    hangingPermission(t)
    serviceBehavior(t)
    coalescence(t)
    distributedNotification(t)
    artworkBehavior(t)
    if let dir = ProcessInfo.processInfo.environment["AURA_MEDIA_RENDER_DIR"] { render(t, to: dir) }
}

@MainActor private func parsing(_ t: SelfCheck) {
    let music: [AnyHashable: Any] = ["Player State": "Playing", "Name": "So What", "Artist": "Miles Davis",
                                     "Album": "Kind of Blue", "Total Time": 562_000]
    t.expect(PlayerPayload.parse(music) == .item(MediaItem(title: "So What", artist: "Miles Davis", duration: 562, isPlaying: true)), "Music playing")
    var paused = music; paused["Player State"] = "Paused"
    if case .item(let i) = PlayerPayload.parse(paused) { t.expect(!i.isPlaying, "paused") } else { t.expect(false, "paused parse") }
    t.expect(PlayerPayload.parse(["Player State": "Stopped"]) == .stopped, "stopped sin metadatos")
    t.expect(PlayerPayload.parse([:]) == .invalid, "vacío -> invalid")
    t.expect(PlayerPayload.parse(["Player State": "Buffering", "Name": "x"]) == .invalid, "estado desconocido")
    t.expect(PlayerPayload.parse(["Player State": "Playing"]) == .invalid, "sin Name -> invalid (no borra lo mostrado)")
    t.expect(PlayerPayload.parse(["Player State": "Playing", "Name": "   "]) == .invalid, "Name en blanco")
    if case .item(let i) = PlayerPayload.parse(["Player State": "playing", "Name": "Solo título"]) {
        t.expect(i.artist == nil && i.duration == nil && i.position == nil, "claves ausentes -> nil")
    } else { t.expect(false, "solo título") }
    let weird: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Línea1\nLínea2\t\u{0007}🎵 日本語", "Artist": String(repeating: "A", count: 500),
                                     "Total Time": "abc", "Playback Position": -4]
    if case .item(let i) = PlayerPayload.parse(weird) {
        t.expect(!i.title.contains("\n") && !i.title.contains("\u{0007}") && i.title.contains("🎵") && i.title.contains("日本語"), "caracteres raros")
        t.expect(i.artist?.count == 200, "artista truncado")
        t.expect(i.duration == nil && i.position == nil, "números ilegibles/negativos descartados")
    } else { t.expect(false, "raros") }
    if case .item(let i) = PlayerPayload.parse(["Player State": "Playing", "Name": "S", "Duration": NSNumber(value: 180_000), "Playback Position": 12.5]) {
        t.expect(i.duration == 180 && i.position == 12.5, "formato Spotify")
    } else { t.expect(false, "spotify") }
    t.expect(PlayerPayload.parse(["Player State": 3, "Name": 4]) == .invalid, "tipos erróneos")
}

@MainActor private func priority(_ t: SelfCheck) {
    typealias C = SourceCandidate
    t.expect(MediaPriority.choose([], manual: nil) == nil, "sin fuentes")
    t.expect(MediaPriority.choose([C(id: "a", isPlaying: true, activity: 1), C(id: "b", isPlaying: false, activity: 5)], manual: nil) == "a", "gana el que reproduce")
    t.expect(MediaPriority.choose([C(id: "a", isPlaying: true, activity: 1), C(id: "b", isPlaying: true, activity: 5)], manual: nil) == "b", "ambos reproducen: el más reciente")
    t.expect(MediaPriority.choose([C(id: "a", isPlaying: false, activity: 9), C(id: "b", isPlaying: false, activity: 5)], manual: nil) == "a", "ninguno: último activo")
    t.expect(MediaPriority.choose([C(id: "a", isPlaying: true, activity: 9), C(id: "b", isPlaying: false, activity: 5)], manual: "b") == "b", "manual manda")
    t.expect(MediaPriority.choose([C(id: "a", isPlaying: true, activity: 9)], manual: "b") == "a", "manual sin contenido: se ignora")
}

@MainActor private func controls(_ t: SelfCheck) {
    let none = MediaControls([.openSource], isPlaying: true)
    t.expect(!none.previous && !none.next && !none.playPause && !none.seek && none.open, "sin permiso: solo abrir")
    let full = MediaControls([.play, .pause, .skip, .seek, .openSource], isPlaying: true)
    t.expect(full.previous && full.next && full.playPause && full.seek && full.open, "todo")
    t.expect(!MediaControls([.play], isPlaying: true).playPause, "reproduciendo sin .pause: sin botón")
    t.expect(MediaControls([.play], isPlaying: false).playPause, "pausado con .play: botón")
    t.expect(!MediaControls([], isPlaying: false).open, "sin openSource no hay abrir")
}

@MainActor private func providerBehavior(_ t: SelfCheck) {
    let tr = FakeTransport()
    let p = MusicProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .notDetermined))
    var done = false
    Task {
        let st_p = await p.authorizationState; t.expect(st_p == .notDetermined, "notDetermined sin diálogo")
        t.expect(p.capabilities == [.openSource], "sin permiso: solo openSource")
        do { try await p.play(); t.expect(false, "play sin permiso debe fallar") } catch { t.expect(error as? MediaError == .notAuthorized, "notAuthorized") }
        t.expect(tr.scripts.isEmpty, "sin permiso NO se envía ningún script")

        let ok = MusicProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .authorized))
        let st_ok = await ok.authorizationState; t.expect(st_ok == .authorized, "authorized")
        t.expect(ok.capabilities.contains(.play) && ok.capabilities.contains(.seek) && !ok.capabilities.contains(.artwork), "capacidades honestas")
        try? await ok.play(); try? await ok.skip(forward: false); try? await ok.seek(to: 42.25)
        t.expect(tr.scripts == ["tell application id \"com.apple.Music\" to play",
                                "tell application id \"com.apple.Music\" to previous track",
                                "tell application id \"com.apple.Music\" to set player position to 42.2"], "scripts \(tr.scripts)")

        tr.result = .failure(.timeout)
        do { try await ok.pause(); t.expect(false, "timeout") } catch let e as MediaError {
            t.expect(e == .timeout && e.errorDescription?.contains("no respondió") == true, "timeout legible")
        } catch { t.expect(false, "tipo") }
        tr.result = .failure(.permissionDenied)
        do { try await ok.pause() } catch let e as MediaError { t.expect(e.errorDescription?.contains("Automatización") == true, "denegado legible") } catch {}
        t.expect(ok.capabilities == [.openSource], "tras -1743 se retiran los controles")
        t.expect(MediaError.appNotRunning.errorDescription?.isEmpty == false && MediaError.failed("x").errorDescription?.contains("x") == true, "mensajes")

        let denied = MusicProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .denied))
        let st_denied = await denied.authorizationState; t.expect(st_denied == .denied, "denied")
        do { try await denied.play() } catch { t.expect(error as? MediaError == .permissionDenied, "denied -> permissionDenied") }

        let off = SpotifyProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .targetNotRunning))
        let st_off = await off.authorizationState; t.expect(st_off == .notDetermined, "app cerrada: se conserva notDetermined")
        do { _ = try await off.requestAuthorization(); t.expect(false, "debía fallar") } catch { t.expect(error as? MediaError == .appNotRunning, "solicitar con app cerrada") }
        t.expect(off.id == "spotify", "id spotify")
        done = true
    }
    pump(2, until: { done })
    t.expect(done, "providerBehavior terminó")
}

@MainActor private func serviceBehavior(_ t: SelfCheck) {
    let a = FakeProvider("music"), b = FakeProvider("spotify")
    let s = MediaService(providers: [a, b])
    t.expect(s.state == .loading, "estado inicial loading")
    s.start()
    pump(0.05) // deja que las tareas se suscriban a los proveedores
    var refreshed = false
    Task { await s.refreshAuthorization(); refreshed = true }
    pump(0.5, until: { refreshed })
    t.expect(s.state == .noPlayer, "sin items: noPlayer")
    a.send(song("A", playing: true)); pump(0.1, until: { s.current != nil })
    t.expect(s.state == .ready && s.current?.providerID == "music", "A reproduce")
    b.send(song("B", playing: true)); pump(0.1, until: { s.current?.providerID == "spotify" })
    t.expect(s.current?.providerID == "spotify", "ambos reproducen: el último")
    b.send(song("B", playing: false)); pump(0.1, until: { s.current?.providerID == "music" })
    t.expect(s.current?.providerID == "music", "B pausa: gana A que reproduce")
    s.selectSource("spotify"); t.expect(s.current?.providerID == "spotify", "selección manual")
    t.expect(s.sources == ["music", "spotify"], "fuentes")
    a.send(nil); b.send(nil); pump(0.1, until: { s.current == nil })
    t.expect(s.current == nil && s.state == .noPlayer && s.compactInfo == nil, "pérdida de fuente limpia metadatos")

    a.send(song("Una canción con un título larguísimo", playing: true)); pump(0.1, until: { s.current != nil })
    t.expect(s.compactInfo?.activity == .media(playing: true) && s.compactInfo?.detail == "Una canción con un título larguísimo", "compacto \(s.compactInfo?.detail ?? "nil")")
    var d = false
    Task { await s.togglePlayPause(); await s.skip(forward: true); d = true }
    pump(0.5, until: { d })
    t.expect(a.calls == ["pause", "next"], "acciones: \(a.calls)")
    a.failure = .timeout
    d = false; Task { await s.togglePlayPause(); d = true }; pump(0.5, until: { d })
    t.expect(s.actionError?.contains("no respondió") == true, "error de acción legible")
    a.failure = nil
    d = false; Task { await s.skip(forward: false); d = true }; pump(0.5, until: { d })
    t.expect(s.actionError == nil, "el error se limpia tras éxito")
    s.stop()

    let empty = MediaService(providers: []); empty.start()
    if case .error = empty.state { t.expect(true, "") } else { t.expect(false, "sin proveedores -> error") }

    let c = FakeProvider("music", caps: [.openSource], auth: .notDetermined)
    let s2 = MediaService(providers: [c]); s2.start()
    pump(0.05)
    refreshed = false
    Task { await s2.refreshAuthorization(); refreshed = true }
    pump(0.5, until: { refreshed })
    c.send(song()); pump(0.1, until: { s2.current != nil })
    t.expect(s2.current?.capabilities == [.openSource] && s2.current?.authorization == .notDetermined, "refleja falta de permiso")
    d = false; Task { await s2.requestAuthorization(); d = true }; pump(0.5, until: { d })
    t.expect(c.calls == ["auth"] && s2.current?.capabilities.contains(.play) == true, "conceder actualiza capacidades")
    s2.stop()
}

@MainActor private func coalescence(_ t: SelfCheck) {
    var clock = Date(timeIntervalSince1970: 1_000)
    let p = FakeProvider("spotify")
    let s = MediaService(providers: [p], now: { clock })
    s.start(); pump(0.05)
    p.send(song(pos: 10)); pump(0.1, until: { s.current != nil })
    let base = s.renderRevision, epoch = s.positionEpoch
    for i in 1...40 {  // ticks de progreso coherentes con el reloj (se procesa cada uno antes de avanzar el reloj)
        clock = clock.addingTimeInterval(0.5)
        p.send(song(pos: 10 + Double(i) * 0.5))
        pump(0.03)
    }
    t.expect(s.renderRevision == base && s.positionEpoch == epoch, "40 ticks no re-renderizan (\(s.renderRevision - base))")
    t.expect(abs((s.position(at: clock) ?? -1) - 30) < 0.01, "posición \(s.position(at: clock) ?? -1)")
    t.expect(abs((s.position(at: clock.addingTimeInterval(5)) ?? -1) - 35) < 0.01, "interpola mientras reproduce")
    p.send(song(pos: 150)); pump(0.1, until: { s.positionEpoch != epoch })
    t.expect(s.positionEpoch == epoch + 1, "seek externo sí redibuja una vez")
    p.send(song(playing: false, pos: 150)); pump(0.1, until: { s.current?.item.isPlaying == false })
    t.expect(s.position(at: clock.addingTimeInterval(30)) == 150, "pausado no avanza")
    p.send(song(playing: false, pos: 150)); p.send(song(playing: false, pos: 150)); pump(0.1)
    let r = s.renderRevision; p.send(song(playing: false, pos: 150)); pump(0.1)
    t.expect(s.renderRevision == r, "eventos idénticos no cambian nada")
    p.send(nil); pump(0.1, until: { s.current == nil })
    t.expect(s.position(at: clock) == nil, "sin fuente no hay posición")
    s.stop()
}

/// Notificación sintética con nombre y claves «realistas»; el formato real sigue POR VERIFICAR con reproducción real.
@MainActor private func distributedNotification(_ t: SelfCheck) {
    let provider = MusicProvider(transport: FakeTransport(), permission: FakePermission(status: .notDetermined))
    var got: [MediaItem?] = []
    let task = Task { for await i in provider.observe() { got.append(i) } }
    pump(0.2)
    let center = DistributedNotificationCenter.default()
    let name = Notification.Name("com.apple.Music.playerInfo")
    center.postNotificationName(name, object: nil, userInfo: ["Player State": "Playing", "Name": "Sintética", "Artist": "Prueba", "Album": "QA", "Total Time": 123_000], deliverImmediately: true)
    center.postNotificationName(name, object: nil, userInfo: ["Garbage": 1], deliverImmediately: true)
    center.postNotificationName(name, object: nil, userInfo: ["Player State": "Stopped"], deliverImmediately: true)
    pump(2, until: { got.count >= 2 })
    t.expect(got.count == 2, "DNC: 2 eventos (basura ignorada), hubo \(got.count)")
    if got.count == 2 {
        t.expect(got[0]?.title == "Sintética" && got[0]?.duration == 123 && got[0]?.isPlaying == true, "DNC: item")
        t.expect(got[1] == nil, "DNC: Stopped -> nil")
    }
    task.cancel()
}

// MARK: - Render

@MainActor private func render(_ t: SelfCheck, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func shot(_ name: String, _ s: MediaService) {
        let v = MediaView(service: s).frame(width: 520, height: 190).background(Color.black).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 190)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = host; win.appearance = NSAppearance(named: .darkAqua)
        pump(0.3)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { t.expect(false, "sin bitmap \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { t.expect(false, "sin PNG \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    func service(_ p: [FakeProvider], items: [(Int, MediaItem?)] = []) -> MediaService {
        let s = MediaService(providers: p); s.start()
        pump(0.2, until: { s.state == .noPlayer })
        for (i, it) in items { p[i].send(it) }
        pump(0.15, until: { s.current != nil || items.isEmpty })
        return s
    }
    shot("media-loading", MediaService(providers: [FakeProvider("music")]))
    shot("media-noplayer", service([FakeProvider("music")]))
    let err = MediaService(providers: []); err.start(); shot("media-error", err)
    let full = FakeProvider("music", caps: [.play, .pause, .skip, .seek, .openSource])
    shot("media-ready-playing", service([full], items: [(0, song("So What", pos: 83))]))
    shot("media-ready-paused-noposition", service([full], items: [(0, MediaItem(title: "Título extremadamente largo que no cabe en una sola línea del panel", artist: "Un artista con nombre largo", duration: 562, isPlaying: false))]))
    shot("media-needs-permission", service([FakeProvider("music", caps: [.openSource], auth: .notDetermined)], items: [(0, song("Sin permiso"))]))
    shot("media-permission-denied", service([FakeProvider("spotify", caps: [.openSource], auth: .denied)], items: [(0, song("Denegado", playing: false))]))
    shot("media-two-sources", service([FakeProvider("music"), FakeProvider("spotify")], items: [(0, song("Dos fuentes")), (1, song("Otra", playing: false))]))
}

// MARK: - Portada

/// Cargador falso: cuenta peticiones, puede fallar o tardar (respetando la cancelación).
private final class FakeLoader: ArtworkDataLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = [], _cancelled = 0
    var delay: Double = 0, fails = false, payload = Data()
    var urls: [URL] { lock.withLock { _urls } }
    var cancelled: Int { lock.withLock { _cancelled } }
    func data(from url: URL) async throws -> Data {
        lock.withLock { _urls.append(url) }
        if delay > 0 {
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1e9)) } catch { lock.withLock { _cancelled += 1 }; throw error }
        }
        if fails { throw URLError(.cannotConnectToHost) }
        return payload
    }
}

private func pngData(side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

@MainActor private func artworkBehavior(_ t: SelfCheck) {
    let big = pngData(side: 800)
    let url = URL(string: "https://i.scdn.co/image/a")!, url2 = URL(string: "https://i.scdn.co/image/b")!

    // Transporte: scripts, permiso y datos.
    let tr = FakeTransport()
    var done = false
    Task {
        let music = MusicProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .authorized))
        let none = await music.artworkLocation()
        t.expect(none == nil && tr.scripts.isEmpty, "sin permiso concedido NO se pide portada ni se envía script")
        _ = await music.authorizationState
        tr.data = big
        let loc = await music.artworkLocation()
        t.expect(loc == .data(big) && tr.scripts.last?.contains("data of artwork 1 of current track") == true, "Música: bytes de la portada")
        t.expect(tr.scripts.last?.contains("is running") == true, "el script no relanza el reproductor")
        tr.data = Data()
        let empty = await music.artworkLocation(); t.expect(empty == nil, "sin portada: nil")
        tr.result = .failure(.failed("x"))
        let failed = await music.artworkLocation(); t.expect(failed == nil, "error del script: nil")

        let sp = SpotifyProvider(feed: FakeFeed(), transport: tr, permission: FakePermission(status: .authorized))
        _ = await sp.authorizationState
        tr.result = .success("https://i.scdn.co/image/a\n")
        let remote = await sp.artworkLocation()
        t.expect(remote == .remote(url) && tr.scripts.last?.contains("artwork url of current track") == true, "Spotify: URL")
        tr.result = .success("")
        let noURL = await sp.artworkLocation(); t.expect(noURL == nil, "URL vacía: nil")
        done = true
    }
    pump(2, until: { done })
    t.expect(done, "artwork/proveedor terminó")

    // Reducción y validación.
    let thumb = ArtworkImageProbe.thumbnail(big)
    t.expect(thumb.map { NSImage(data: $0).map { max($0.size.width, $0.size.height) <= 256 } ?? false } == true, "miniatura <= 256 px")
    t.expect(ArtworkImageProbe.thumbnail(Data("no soy una imagen".utf8)) == nil, "bytes que no son imagen se descartan")
    t.expect(ArtworkImageProbe.thumbnail(Data(count: 5_000_000)) == nil, "por encima del tamaño máximo se descarta")

    // Servicio: dobles de proveedor y de red.
    func make(_ loader: FakeLoader, _ p: FakeProvider) -> MediaService {
        let s = MediaService(providers: [p], artworkLoader: loader)
        s.start(); pump(0.05)
        var r = false; Task { await s.refreshAuthorization(); r = true }; pump(0.5, until: { r })
        return s
    }
    let loader = FakeLoader(); loader.payload = big
    let sp = FakeProvider("spotify"); sp.artwork = .remote(url)
    let s = make(loader, sp)
    sp.send(song("A")); pump(1, until: { s.current?.item.artworkData != nil })
    t.expect(s.current?.item.artworkData != nil && loader.urls == [url], "Spotify: portada descargada una vez")
    let first = s.current?.item.artworkData
    sp.send(song("A", playing: false)); pump(0.2)
    t.expect(s.current?.item.artworkData == first && loader.urls.count == 1, "pausar no pierde la portada ni descarga otra vez")
    sp.send(song("B")); pump(1, until: { s.current?.item.title == "B" && s.current?.item.artworkData != nil })
    t.expect(s.current?.item.artworkData == first && loader.urls.count == 1, "misma URL: sirve la caché en memoria")
    sp.artwork = .remote(url2)
    sp.send(song("C")); pump(1, until: { loader.urls.count == 2 })
    t.expect(loader.urls == [url, url2], "URL distinta: nueva descarga")
    s.stop()

    // Ajuste desactivado, http, fallo y datos corruptos: placeholder, sin error visible.
    let l2 = FakeLoader(); l2.payload = big
    let p2 = FakeProvider("spotify"); p2.artwork = .remote(url)
    let s2 = make(l2, p2); s2.loadsRemoteArtwork = false
    p2.send(song("A")); pump(0.3)
    t.expect(l2.urls.isEmpty && s2.current?.item.artworkData == nil && s2.state == .ready, "con el ajuste desactivado no hay red")
    s2.loadsRemoteArtwork = true; pump(1, until: { s2.current?.item.artworkData != nil })
    t.expect(s2.current?.item.artworkData != nil, "al reactivar el ajuste se carga la portada de la pista actual")
    s2.stop()

    let l3 = FakeLoader(); l3.payload = big
    let p3 = FakeProvider("spotify"); p3.artwork = .remote(URL(string: "http://i.scdn.co/image/a")!)
    let s3 = make(l3, p3); p3.send(song("A")); pump(0.3)
    t.expect(l3.urls.isEmpty && s3.current?.item.artworkData == nil, "http se rechaza sin red")
    p3.artwork = .remote(url); l3.fails = true; p3.send(song("B")); pump(0.3, until: { l3.urls.count == 1 })
    pump(0.2)
    t.expect(s3.current?.item.artworkData == nil && s3.state == .ready && s3.actionError == nil, "fallo de red: placeholder sin error")
    l3.fails = false; l3.payload = Data("basura".utf8); p3.send(song("C")); pump(0.3, until: { l3.urls.count == 2 })
    pump(0.2)
    t.expect(s3.current?.item.artworkData == nil, "datos que no son imagen: placeholder")
    s3.stop()

    // Cancelación al cambiar de canción.
    let l4 = FakeLoader(); l4.payload = big; l4.delay = 0.5
    let p4 = FakeProvider("spotify"); p4.artwork = .remote(url)
    let s4 = make(l4, p4); p4.send(song("A")); pump(0.15, until: { l4.urls.count == 1 })
    p4.send(song("B")); pump(0.3, until: { l4.cancelled == 1 })
    t.expect(l4.cancelled == 1, "cambiar de pista cancela la descarga en curso")
    s4.stop()

    // Música (bytes locales): no usa red ni depende del ajuste.
    let l5 = FakeLoader()
    let p5 = FakeProvider("music"); p5.artwork = .data(big)
    let s5 = make(l5, p5); s5.loadsRemoteArtwork = false
    p5.send(song("M")); pump(1, until: { s5.current?.item.artworkData != nil })
    t.expect(s5.current?.item.artworkData != nil && l5.urls.isEmpty, "Música: portada local sin tocar la red")
    s5.stop()
}

/// `ArtworkImage` es interno al módulo: se prueba a través del descarte/reducción visibles del servicio.
private enum ArtworkImageProbe {
    @MainActor static func thumbnail(_ data: Data) -> Data? {
        let l = FakeLoader(); l.payload = data
        let p = FakeProvider("spotify"); p.artwork = .remote(URL(string: "https://x.test/i")!)
        let s = MediaService(providers: [p], artworkLoader: l)
        s.start(); pump(0.05)
        var r = false; Task { await s.refreshAuthorization(); r = true }; pump(0.5, until: { r })
        p.send(song("T")); pump(0.4, until: { s.current?.item.artworkData != nil })
        defer { s.stop() }
        return s.current?.item.artworkData
    }
}

/// Regresión: una consulta de permiso bloqueada no debe colgar al proveedor ni apilar hilos.
@MainActor private func hangingPermission(_ t: SelfCheck) {
    let perm = HangingPermission()
    let suite = "aura.test.media-remember"
    let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
    // El permiso ya concedido se recuerda entre arranques (la consulta silenciosa de Spotify no contesta)...
    d.set(true, forKey: "aura.media.automation-granted.\(PlayerSpec.spotify.bundleID)")
    let remembered = SpotifyProvider(feed: FakeFeed(), transport: FakeTransport(), permission: perm, remembered: d)
    t.expect(remembered.capabilities.contains(.play), "permiso recordado: arranca con control")
    // ...y si macOS lo deniega después, se olvida.
    let denyTransport = FakeTransport(); denyTransport.result = .failure(.permissionDenied)
    let revoked = SpotifyProvider(feed: FakeFeed(), transport: denyTransport, permission: perm, remembered: d)
    var gone = false
    Task { try? await revoked.play(); gone = true }
    let end0 = Date().addingTimeInterval(3)
    while !gone && Date() < end0 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    t.expect(!revoked.capabilities.contains(.play) && d.bool(forKey: "aura.media.automation-granted.\(PlayerSpec.spotify.bundleID)") == false, "permiso revocado: se olvida")
    d.removePersistentDomain(forName: suite)
    let it = ScriptablePlayerProvider.parseInitial("playing\nBandido\nConep\n209000\n47,5", durationIsMilliseconds: true)
    t.expect(it?.title == "Bandido" && it?.artist == "Conep" && it?.isPlaying == true && it?.duration == 209 && it?.position == 47.5, "estado inicial de Spotify (ms, coma decimal)")
    let it2 = ScriptablePlayerProvider.parseInitial("paused\nCanción\nArtista\n180.5\n3", durationIsMilliseconds: false)
    t.expect(it2?.isPlaying == false && it2?.duration == 180.5, "estado inicial de Música (segundos)")
    t.expect(ScriptablePlayerProvider.parseInitial("", durationIsMilliseconds: true) == nil, "sin reproductor: sin estado inicial")
    let p = MusicProvider(feed: FakeFeed(), transport: FakeTransport(), permission: perm)
    var done = false
    Task {
        let t0 = Date()
        let a = await p.authorizationState
        t.expect(Date().timeIntervalSince(t0) < 3, "consulta bloqueada: vuelve por timeout (<3 s)")
        t.expect(a == .notDetermined, "tras timeout conserva el último valor")
        _ = await p.authorizationState; _ = await p.authorizationState
        t.expect(perm.callCount == 1, "no apila consultas mientras hay una pendiente (\(perm.callCount))")
        done = true
    }
    let end = Date().addingTimeInterval(10)
    while !done && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    t.expect(done, "hangingPermission terminó")
}
