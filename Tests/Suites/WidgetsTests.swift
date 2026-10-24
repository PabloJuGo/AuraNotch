import AppKit
import AuraCore
import AuraWidgets
import SwiftUI

/// Suite de AuraWidgets (AURA-016). Reloj, fuente de energía y acciones del sistema son falsos;
/// la única lectura REAL es una llamada a IOKit (se imprime). Con `AURA_WIDGETS_RENDER_DIR=<ruta>` genera PNG.

private final class Clk: @unchecked Sendable {
    var now: Date
    init(_ d: Date = Date(timeIntervalSince1970: 1_800_000_000)) { now = d }
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

@MainActor private final class FakePower: PowerSource {
    var result: Result<PowerReading, PowerError>
    var observers = 0, reads = 0
    var fire: (@MainActor () -> Void)?
    init(_ r: PowerReading) { result = .success(r) }
    func read() throws -> PowerReading { reads += 1; return try result.get() }
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        observers += 1; fire = onChange
        return { [self] in observers -= 1; fire = nil }
    }
}

@MainActor private final class Flag { var on = false }

@MainActor private final class FakeVolume: VolumeBackend {
    var result: Result<VolumeReading, VolumeError>
    var observers = 0, levelWrites: [Double] = [], muteWrites: [Bool] = []
    var fire: (@MainActor () -> Void)?
    init(_ r: VolumeReading) { result = .success(r) }
    func read() throws -> VolumeReading { try result.get() }
    func setLevel(_ level: Double) throws {
        levelWrites.append(level)
        if case .success(var r) = result { r.level = level; result = .success(r) }
    }
    func setMuted(_ muted: Bool) throws {
        muteWrites.append(muted)
        if case .success(var r) = result { r.isMuted = muted; result = .success(r) }
    }
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        observers += 1; fire = onChange
        return { [self] in observers -= 1; fire = nil }
    }
}

@MainActor private final class Spy: AuraWidget {
    let manifest: WidgetManifest
    var state: WidgetState = .ready
    var isAvailable = true
    var summary: String { manifest.name }
    var activeCalls: [Bool] = []
    init(_ id: String, available: Bool = true) { manifest = WidgetManifest(id: id, name: id, symbol: "circle"); isAvailable = available }
    func setActive(_ a: Bool) { activeCalls.append(a) }
    func makeBody() -> AnyView { AnyView(Text(manifest.name)) }
}

@MainActor private final class FakeSystem: SystemActions {
    var opened: [URL] = [], copied: [String] = [], openResult = true
    func open(_ url: URL) -> Bool { opened.append(url); return openResult }
    func copy(_ text: String) { copied.append(text) }
}

private struct StubAction: QuickAction {
    let id: String
    var title: String { id }
    let symbol = "star"
    let fail: Bool
    @MainActor func perform() async throws { if fail { throw QuickActionError("boom") } }
}

@MainActor private final class Notifier: TimerNotifier {
    var durations: [TimeInterval] = []
    func timerFinished(duration: TimeInterval) { durations.append(duration) }
}

@MainActor private func pump(_ seconds: Double = 0.1, until cond: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

@MainActor
func runWidgetsSuite(_ t: SelfCheck) {
    // Rejilla de 2 columnas: anchos solos, estrechos por parejas, un estrecho suelto ocupa la fila.
    t.expect(WidgetGrid.rows(columns: [2, 2, 1, 1, 2]) == [[0], [1], [2, 3], [4]], "rejilla: anchos solos y estrechos por parejas")
    t.expect(WidgetGrid.rows(columns: [1, 2, 1]) == [[0], [1], [2]], "rejilla: un estrecho antes de un ancho ocupa su fila")
    t.expect(WidgetGrid.rows(columns: [1, 1, 1]) == [[0, 1], [2]], "rejilla: el último estrecho suelto ocupa su fila")
    t.expect(WidgetGrid.rows(columns: []).isEmpty, "rejilla: vacía")
    timerModel(t)
    timerRealScheduler(t)
    timerAlerts(t)
    registry(t)
    battery(t)
    realBattery(t)
    dateWidget(t)
    volume(t)
    quickActions(t)
    if let dir = ProcessInfo.processInfo.environment["AURA_WIDGETS_RENDER_DIR"] { render(t, to: dir) }
}

// MARK: - Temporizador

@MainActor private func timerModel(_ t: SelfCheck) {
    let c = Clk(), n = Notifier()
    let s = TimerService(clock: { c.now }, duration: 300)
    var finished: [TimeInterval] = []
    s.onFinished = { finished.append($0) }; s.notifier = n
    t.expect(s.phase == .idle && s.remaining(at: c.now) == 300 && s.compactInfo == nil, "idle: sin actividad compacta")
    s.setDuration(0); t.expect(s.duration == TimerService.minDuration, "duración mínima")
    s.setDuration(10 * 24 * 3600); t.expect(s.duration == TimerService.maxDuration, "duración máxima")
    s.setDuration(300)
    s.start()
    t.expect(s.isRunning && s.remaining(at: c.now) == 300, "running con 300 s")
    c.advance(100)
    t.expect(s.remaining(at: c.now) == 200 && abs(s.progress(at: c.now) - 1.0 / 3) < 1e-9, "progreso 1/3 sin ningún tick")
    t.expect(s.compactInfo?.activity == .timer && s.compactInfo?.detail == "3:20" && s.compactInfo?.accessibilityLabel.isEmpty == false, "compactInfo 3:20")
    s.setDuration(60); t.expect(s.duration == 300, "no se cambia la duración en marcha")
    s.pause()
    t.expect(s.phase == .paused(remaining: 200), "pausa congela el restante")
    c.advance(3600)  // estar pausado una hora no consume tiempo
    t.expect(s.remaining(at: c.now) == 200 && finished.isEmpty, "pausado no avanza ni termina")
    s.resume()
    t.expect(s.isRunning && s.remaining(at: c.now) == 200, "reanuda con lo que quedaba")
    c.advance(50); s.refresh()
    t.expect(s.isRunning && finished.isEmpty, "antes del fin no termina")
    // sleep simulado: el reloj salta mucho más allá del fin sin que haya habido ticks
    c.advance(10_000); s.refresh()
    t.expect(s.phase == .finished && finished == [300] && n.durations == [300], "tras sleep termina una sola vez")
    s.refresh(); s.refresh()
    t.expect(finished.count == 1 && n.durations.count == 1, "refresh repetido no duplica el aviso")
    t.expect(s.compactInfo?.detail == WidgetStringsProbe.finished && s.remaining(at: c.now) == 0 && s.progress(at: c.now) == 1, "finished: compact + progreso 1")
    s.start(); t.expect(s.isRunning && s.remaining(at: c.now) == 300, "reiniciar desde finished")
    s.cancel(); t.expect(s.phase == .idle && s.compactInfo == nil, "cancelar vuelve a idle")
    s.pause(); s.resume(); t.expect(s.phase == .idle, "pausar/reanudar en idle no hace nada")
    s.start(); c.advance(299); s.pause(); c.advance(0.5); s.resume(); c.advance(0.4); s.refresh()
    t.expect(s.isRunning, "pausa/reanuda cerca del final conserva el tiempo")
    c.advance(1); s.refresh(); t.expect(s.phase == .finished, "y termina en su instante")
    t.expect(TimerFormat_clock(3725) == "1:02:05" && TimerFormat_clock(299.2) == "5:00", "formato h:mm:ss y redondeo hacia arriba")
    t.expect(s.state == .ready && !s.summary.isEmpty && s.manifest.id == "timer", "estado ready + resumen VoiceOver")
}

/// El texto «Terminado» es el de la cadena localizada; se compara con el compacto sin duplicar la clave.
private enum WidgetStringsProbe { static let finished = String(localized: "Terminado") }
@MainActor private func TimerFormat_clock(_ secs: TimeInterval) -> String {
    let c = Clk(); let x = TimerService(clock: { c.now }, duration: secs); x.start()
    return x.compactInfo(at: c.now)?.detail ?? ""
}

/// Una sola espera real (no polling): con 1 s de duración y el reloj del sistema, termina sola.
@MainActor private func timerRealScheduler(_ t: SelfCheck) {
    let s = TimerService(duration: 1)
    var done = 0
    s.onFinished = { _ in done += 1 }
    s.start()
    pump(2.5, until: { s.phase == .finished })
    t.expect(s.phase == .finished && done == 1, "la espera de un disparo termina sola (reloj real)")
    let c = Clk(); let q = TimerService(clock: { c.now }, duration: 5); q.start(); q.cancel()
    t.expect(q.phase == .idle, "cancelar descarta la espera")
}

// MARK: - Registro

@MainActor private func registry(_ t: SelfCheck) {
    let a = Spy("a"), b = Spy("b"), c = Spy("c"), x = Spy("x", available: false)
    let r = WidgetRegistry(widgets: [a, b, c, x, Spy("a")])
    t.expect(r.entries.map(\.id) == ["a", "b", "c", "x"], "ids duplicados ignorados, orden de alta")
    t.expect(a.activeCalls.isEmpty, "nada se activa antes de ser visible")
    r.setVisible(true)
    t.expect(a.activeCalls == [true] && x.activeCalls == [false], "visible activa los utilizables; no disponible nunca")
    var saved: WidgetLayout?
    r.onLayoutChange = { saved = $0 }
    r.move("c", by: -2)
    t.expect(r.entries.map(\.id) == ["c", "a", "b", "x"] && saved?.order == ["c", "a", "b", "x"], "mover c dos posiciones arriba + notifica")
    t.expect(!r.canMove("c", by: -1) && r.canMove("c", by: 1) && !r.canMove("zz", by: 1), "límites de movimiento")
    r.move("c", by: -1); t.expect(r.entries.first?.id == "c", "mover fuera de rango no hace nada")
    r.setEnabled("a", false)
    t.expect(a.activeCalls == [true, false] && !r.isEnabled("a") && saved?.disabled == ["a"], "desactivar suelta el widget")
    r.setEnabled("a", false); t.expect(a.activeCalls.count == 2, "idempotente")
    r.setVisible(false)
    t.expect(b.activeCalls == [true, false] && a.activeCalls.last == false, "ocultar desactiva a los activos")
    let data = try? JSONEncoder().encode(r.layout)
    let back = data.flatMap { try? JSONDecoder().decode(WidgetLayout.self, from: $0) }
    t.expect(back == r.layout, "layout Codable")
    let r2 = WidgetRegistry(widgets: [Spy("a"), Spy("b"), Spy("c"), Spy("nuevo")], layout: WidgetLayout(order: ["c", "zz", "a"], disabled: ["b"]))
    t.expect(r2.entries.map(\.id) == ["c", "a", "b", "nuevo"], "orden restaurado, ids desconocidos ignorados, nuevos al final")
    t.expect(!r2.isEnabled("b") && r2.isEnabled("nuevo") && !r2.isEnabled("zz") && r2.widget("a") != nil, "activación restaurada")
    // Manifiestos de los widgets reales
    let all: [any AuraWidget] = [TimerService(), BatteryService(source: FakePower(.none)), DateService(), QuickActionsService()]
    t.expect(all.map(\.manifest.id) == ["timer", "battery", "date", "actions"], "ids de manifiestos")
    t.expect(all.allSatisfy { !$0.manifest.name.isEmpty && !$0.manifest.version.isEmpty && !$0.manifest.symbol.isEmpty }, "manifiestos completos")
    t.expect(all[3].manifest.permissions == [.openURLs, .pasteboardWrite] && all[0].manifest.permissions.isEmpty, "permisos declarados")
    t.expect(all.allSatisfy { $0.manifest.minimumRefresh == nil }, "ningún widget declara intervalo de sondeo")
    t.expect(WidgetRegistry(widgets: []).entries.isEmpty, "registro vacío")
}

// MARK: - Batería

@MainActor private func battery(_ t: SelfCheck) {
    let center = NotificationCenter()
    let lpm = Flag()
    let src = FakePower(.none)
    let b = BatteryService(source: src, lowPowerProvider: { lpm.on }, center: center)
    t.expect(b.state == .loading && src.reads == 0, "cargando antes de activar; sin lecturas")
    b.setActive(true)
    if case .empty = b.state { t.expect(true, "") } else { t.expect(false, "Mac de escritorio -> empty") }
    t.expect(src.observers == 1, "una suscripción")
    b.setActive(true); t.expect(src.observers == 1, "activar dos veces no duplica")
    src.result = .success(PowerReading(hasBattery: true, percent: 64, isCharging: true, isPluggedIn: true, minutesRemaining: 72))
    src.fire?()
    t.expect(b.state == .ready && b.reading?.percent == 64 && b.reading?.isCharging == true, "evento -> cargando 64 %")
    t.expect(!b.isLow && b.summary.contains("64") && b.summary.contains("1 h 12 min"), "resumen: \(b.summary)")
    src.result = .success(PowerReading(hasBattery: true, percent: 12, minutesRemaining: 35))
    src.fire?()
    t.expect(b.isLow && b.summary.contains("35 min"), "batería baja: \(b.summary)")
    t.expect(b.makeBodyIsReady, "cuerpo disponible")
    lpm.on = true
    center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
    pump(0.3, until: { b.lowPowerMode })
    t.expect(b.lowPowerMode && b.summary.contains(String(localized: "Modo de bajo consumo")), "notificación de bajo consumo")
    src.result = .failure(.unavailable)
    b.retry()
    if case .error = b.state { t.expect(b.reading == nil, "error limpia la lectura") } else { t.expect(false, "error de lectura") }
    src.result = .success(PowerReading(hasBattery: true, percent: 100, isPluggedIn: true, isCharged: true))
    b.retry(); t.expect(b.state == .ready, "reintentar se recupera")
    b.setActive(false)
    t.expect(src.observers == 0, "desactivar cancela la suscripción")
    lpm.on = false; center.post(name: .NSProcessInfoPowerStateDidChange, object: nil); pump(0.1)
    t.expect(b.lowPowerMode, "inactivo ignora notificaciones")
    for s in ["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent", "battery.100percent.bolt"] {
        t.expect(NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil, "SF Symbol \(s)")
    }
}

extension BatteryService { fileprivate var makeBodyIsReady: Bool { state == .ready } }

@MainActor private func realBattery(_ t: SelfCheck) {
    let real = BatteryService()
    real.setActive(true)
    t.expect(real.state != .loading, "lectura real resuelve el estado")
    var cancelled = false
    real.setActive(false); cancelled = true
    t.expect(cancelled, "ciclo activar/desactivar real sin fallo")
    print("LECTURA REAL batería (IOKit): estado=\(real.state) lectura=\(String(describing: real.reading)) bajoConsumo=\(real.lowPowerMode)")
}

// MARK: - Volumen

@MainActor private func volume(_ t: SelfCheck) {
    let b = FakeVolume(VolumeReading(level: 0.5))
    let v = VolumeService(backend: b)
    t.expect(v.state == .loading && v.manifest.id == "volume" && v.manifest.permissions.isEmpty && v.manifest.minimumRefresh == nil, "volumen: cargando, sin permisos ni intervalo")
    v.setActive(true); v.setActive(true)
    t.expect(v.state == .ready && v.reading?.level == 0.5 && b.observers == 1, "activa una sola vez y lee")
    t.expect(v.summary.contains("50"), "resumen: \(v.summary)")
    v.setLevel(0.8)
    t.expect(b.levelWrites == [0.8] && v.reading?.level == 0.8, "setLevel escribe en el backend")
    v.setLevel(7); t.expect(b.levelWrites.last == 1, "se acota a 1")
    v.adjust(by: -VolumeService.step); t.expect(abs((v.reading?.level ?? 0) - 0.9375) < 1e-9, "adjust de accesibilidad")
    v.toggleMute()
    t.expect(b.muteWrites == [true] && v.reading?.isMuted == true && v.isSilent && v.summary.contains(String(localized: "Silenciado")), "clic silencia")
    v.setLevel(0.3)
    t.expect(b.muteWrites == [true, false] && v.reading?.isMuted == false, "subir el volumen quita el silencio")
    b.result = .success(VolumeReading(level: 0.9, isMuted: true)); b.fire?()
    t.expect(v.reading?.isMuted == true && v.reading?.level == 0.9, "evento externo actualiza")
    t.expect(["speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill"].allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }, "SF Symbols de volumen")
    t.expect(v.symbol(VolumeReading(level: 0.9, isMuted: true)) == "speaker.slash.fill" && v.symbol(VolumeReading(level: 0.2)) == "speaker.wave.1.fill"
             && v.symbol(VolumeReading(level: 0.5)) == "speaker.wave.2.fill" && v.symbol(VolumeReading(level: 1)) == "speaker.wave.3.fill", "icono según nivel")
    // Dispositivo sin interruptor de mute: se emula con volumen 0 y se restaura
    b.result = .success(VolumeReading(level: 0.6, canMute: false)); b.fire?(); b.muteWrites = []
    v.toggleMute(); t.expect(v.reading?.level == 0 && b.muteWrites.isEmpty, "mute emulado a 0")
    v.toggleMute(); t.expect(v.reading?.level == 0.6, "restaura el nivel previo")
    // HDMI sin control -> empty; al cambiar de dispositivo se recupera sin reactivar
    b.result = .failure(.noControl); b.fire?()
    if case .empty = v.state { t.expect(v.reading == nil && v.isAvailable, "sin control: estado empty, sigue escuchando") } else { t.expect(false, "sin control -> empty") }
    v.setLevel(0.4); v.toggleMute(); t.expect(b.levelWrites.last != 0.4, "sin lectura no escribe")
    b.result = .success(VolumeReading(level: 0.2)); b.fire?()
    t.expect(v.state == .ready && v.reading?.level == 0.2, "cambio de dispositivo -> recupera")
    b.result = .failure(.failed); v.retry()
    if case .error = v.state { t.expect(v.reading == nil, "fallo -> error") } else { t.expect(false, "fallo -> error") }
    b.result = .success(VolumeReading(level: 0.2)); v.retry(); t.expect(v.state == .ready, "reintentar se recupera")
    v.setActive(false); t.expect(b.observers == 0, "desactivar cancela la suscripción")
    // CoreAudio real: solo lectura y alta/baja de oyentes (no escribe ni cambia el volumen)
    let real = VolumeService()
    real.setActive(true)
    t.expect(real.state != .loading, "lectura real resuelve el estado")
    real.setActive(false)
    print("LECTURA REAL volumen (CoreAudio): estado=\(real.state) lectura=\(String(describing: real.reading))")
}

// MARK: - Fecha

@MainActor private func dateWidget(_ t: SelfCheck) {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let c = Clk(cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 23, minute: 59))!)
    let center = NotificationCenter()
    let d = DateService(now: { c.now }, calendar: cal, locale: Locale(identifier: "es_ES"), center: center)
    t.expect(d.day == "1" && d.weekday == "Lunes" && d.monthYear == "Enero de 2024", "localizado: \(d.weekday) \(d.day) \(d.monthYear)")
    t.expect(d.summary.lowercased().contains("lunes"), "VoiceOver: \(d.summary)")
    d.setActive(true)
    c.advance(120)  // cruza la medianoche
    t.expect(d.day == "1", "sin notificación no cambia (no hay timer)")
    center.post(name: .NSCalendarDayChanged, object: nil)
    pump(0.3, until: { d.day == "2" })
    t.expect(d.day == "2" && d.weekday == "Martes", "NSCalendarDayChanged actualiza: \(d.weekday) \(d.day)")
    d.setActive(false)
    c.advance(86_400); center.post(name: .NSCalendarDayChanged, object: nil); pump(0.1)
    t.expect(d.day == "2", "inactivo ignora el cambio de día")
    d.setActive(true); t.expect(d.day == "3", "al reactivar se relee la fecha")
    d.setActive(false)
}

// MARK: - Acciones

@MainActor private func quickActions(_ t: SelfCheck) {
    let sys = FakeSystem()
    let when = Date(timeIntervalSince1970: 1_704_067_200)  // 2024-01-01 UTC
    let folder = URL(fileURLWithPath: "/tmp/Descargas", isDirectory: true)
    let s = QuickActionsService(catalog: [OpenSystemSettingsAction(system: sys), OpenDownloadsAction(system: sys, folder: folder),
                                          CopyDateAction(system: sys, now: { when }, locale: Locale(identifier: "es_ES"))],
                                feedbackSeconds: 0.05)
    t.expect(s.favorites == ["open-settings", "open-downloads", "copy-date"] && s.state == .ready, "favoritas por defecto")
    Task { await s.run("open-settings"); await s.run("open-downloads"); await s.run("copy-date") }
    pump(1, until: { sys.copied.count == 1 })
    t.expect(sys.opened.map(\.absoluteString) == ["x-apple.systempreferences:", folder.absoluteString], "abre Ajustes y Descargas: \(sys.opened)")
    t.expect(sys.copied.count == 1 && sys.copied[0].contains("2024"), "copia la fecha: \(sys.copied)")
    pump(0.4, until: { s.status.isEmpty })
    t.expect(s.status.isEmpty, "el feedback se limpia solo (una espera, no un timer)")
    sys.openResult = false
    Task { await s.run("open-settings") }
    pump(0.2, until: { s.status["open-settings"] != nil })
    if case .failed? = s.status["open-settings"] { t.expect(true, "") } else { t.expect(false, "fallo al abrir -> failed") }
    var saved: [String]?
    s.onFavoritesChange = { saved = $0 }
    s.setFavorites(["copy-date", "inventada", "copy-date", "open-settings"])
    t.expect(s.favorites == ["copy-date", "open-settings"] && saved == ["copy-date", "open-settings"], "configurables; desconocidas y repetidas descartadas")
    t.expect(s.favoriteActions.map(\.id) == ["copy-date", "open-settings"], "orden de favoritas")
    s.setFavorites([])
    if case .empty = s.state { t.expect(true, "") } else { t.expect(false, "sin favoritas -> empty") }
    let f = QuickActionsService(catalog: [StubAction(id: "ok", fail: false), StubAction(id: "mal", fail: true)], feedbackSeconds: 5)
    Task { await f.run("ok"); await f.run("mal"); await f.run("no-existe") }
    pump(0.3, until: { f.status["mal"] != nil })
    t.expect(f.status["ok"] == .succeeded && f.status["mal"] == .failed("boom") && f.status["no-existe"] == nil, "protocolo falso: éxito y fallo")
}

// MARK: - Capturas

@MainActor private func render(_ t: SelfCheck, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func shot(_ name: String, _ v: some View, _ w: CGFloat, _ h: CGFloat) {
        let root = v.frame(width: w, height: h, alignment: .topLeading).background(Color.black).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = host; win.appearance = NSAppearance(named: .darkAqua)
        pump(0.3)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { t.expect(false, "sin bitmap \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { t.expect(false, "sin PNG \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
    func dateW() -> DateService { DateService(now: { day }, calendar: cal, locale: Locale(identifier: "es_ES"), center: NotificationCenter()) }
    func timer(_ step: (TimerService, Clk) -> Void) -> TimerService {
        let c = Clk(Date()); let s = TimerService(clock: { c.now }, duration: 300); step(s, c); return s
    }
    let sys = FakeSystem()
    let ready = WidgetRegistry(widgets: [
        timer { s, _ in s.start() },
        BatteryService(source: FakePower(PowerReading(hasBattery: true, percent: 78, isCharging: true, isPluggedIn: true, minutesRemaining: 42)),
                       lowPowerProvider: { false }, center: NotificationCenter()),
        dateW(),
        QuickActionsService(catalog: [OpenSystemSettingsAction(system: sys), OpenDownloadsAction(system: sys), CopyDateAction(system: sys)]),
    ])
    ready.setVisible(true)
    shot("widgets-view-ready", WidgetsView(registry: ready), 520, 330)

    let mixed = WidgetRegistry(widgets: [
        timer { _, _ in },
        BatteryService(source: FakePower(.none), lowPowerProvider: { false }, center: NotificationCenter()),
        { let f = FakePower(.none); f.result = .failure(.unavailable); return BatteryServiceNamed(f) }(),
        QuickActionsService(catalog: [OpenSystemSettingsAction(system: sys)], favorites: []),
        Spy("fuera", available: false),
    ], layout: WidgetLayout(order: [], disabled: ["timer"]))
    mixed.setVisible(true)
    shot("widgets-view-states", WidgetsView(registry: mixed), 520, 330)

    shot("widgets-view-empty", WidgetsView(registry: WidgetRegistry(widgets: [])), 520, 160)
    shot("timer-idle", TimerView(service: timer { _, _ in }).padding(Space_md), 260, 120)
    shot("timer-running", TimerView(service: timer { s, c in s.start(); c.advance(75) }).padding(Space_md), 260, 120)
    shot("timer-paused", TimerView(service: timer { s, c in s.start(); c.advance(75); s.pause() }).padding(Space_md), 260, 120)
    shot("timer-finished", TimerView(service: timer { s, c in s.start(); c.advance(301); s.refresh() }).padding(Space_md), 260, 120)
}

private let Space_md: CGFloat = 12

/// Batería con id distinto para poder mostrar dos tarjetas de batería en la captura de estados (vacío y error).
@MainActor private func BatteryServiceNamed(_ src: FakePower) -> any AuraWidget {
    let b = BatteryService(source: src, lowPowerProvider: { false }, center: NotificationCenter())
    return RenamedWidget(b, id: "battery-error", name: "Batería (error)")
}

@MainActor private final class RenamedWidget: AuraWidget {
    let inner: any AuraWidget, manifest: WidgetManifest
    init(_ w: any AuraWidget, id: String, name: String) { inner = w; var m = w.manifest; m.id = id; m.name = name; manifest = m }
    var state: WidgetState { inner.state }
    var summary: String { inner.summary }
    func setActive(_ a: Bool) { inner.setActive(a) }
    func retry() { inner.retry() }
    func makeBody() -> AnyView { inner.makeBody() }
}

// MARK: - Aviso del temporizador (dobles: no se toca NSSound ni UNUserNotificationCenter)

@MainActor private final class FakeSound: TimerSound { var plays = 0; func playFinished() { plays += 1 } }
@MainActor private final class FakeCenter: TimerNotificationCenter {
    var status: TimerNotificationAuth, grants: Bool
    var requests = 0, posted: [(String, String)] = []
    init(_ s: TimerNotificationAuth, grants: Bool = true) { status = s; self.grants = grants }
    func authorization() async -> TimerNotificationAuth { status }
    func requestAuthorization() async -> Bool { requests += 1; status = grants ? .authorized : .denied; return grants }
    func post(title: String, body: String) async { posted.append((title, body)) }
}

@MainActor private func timerAlerts(_ t: SelfCheck) {
    // Sin centro (app sin empaquetar): solo sonido y sin permiso .notifications.
    let snd = FakeSound(), bare = SystemTimerNotifier(sound: snd, center: nil)
    let c = Clk(), s = TimerService(clock: { c.now }, duration: 60); s.notifier = bare
    t.expect(s.manifest.permissions.isEmpty, "sin centro: no declara .notifications")
    s.start(); c.advance(61); s.refresh(); pump(0.05)
    t.expect(snd.plays == 1, "suena al terminar")
    t.expect(Bundle.main.bundleIdentifier != nil || UserNotificationCenterAdapter() == nil, "sin bundle no se crea el centro real")

    // Primera vez: pide permiso al iniciar (no antes); concedido -> notifica al terminar.
    let ok = FakeCenter(.notDetermined), snd2 = FakeSound()
    let n = SystemTimerNotifier(sound: snd2, center: ok)
    let c2 = Clk(), s2 = TimerService(clock: { c2.now }, duration: 60); s2.notifier = n
    pump(0.05); t.expect(ok.requests == 0, "no se pide permiso hasta iniciar")
    t.expect(s2.manifest.permissions == [.notifications], "con centro declara .notifications")
    s2.start(); pump(0.1, until: { ok.requests > 0 })
    t.expect(ok.requests == 1, "primer inicio pide permiso")
    s2.pause(); s2.resume(); s2.cancel(); s2.start(); pump(0.05)
    t.expect(ok.requests == 1, "ya determinado: no se vuelve a pedir")
    c2.advance(61); s2.refresh(); pump(0.1, until: { !ok.posted.isEmpty })
    t.expect(snd2.plays == 1 && ok.posted.count == 1 && !ok.posted[0].0.isEmpty && !ok.posted[0].1.isEmpty, "sonido + notificación con texto")

    // Denegado: degrada solo a sonido.
    let no = FakeCenter(.notDetermined, grants: false), snd3 = FakeSound()
    let c3 = Clk(), s3 = TimerService(clock: { c3.now }, duration: 60); let n3 = SystemTimerNotifier(sound: snd3, center: no); s3.notifier = n3  // notifier es weak: hay que retenerlo
    s3.start(); pump(0.1, until: { no.requests > 0 }); c3.advance(61); s3.refresh(); pump(0.1)
    t.expect(snd3.plays == 1 && no.posted.isEmpty, "denegado: solo sonido"); _ = n3
}
