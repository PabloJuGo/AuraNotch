import AppKit
import AuraCalendar
import AuraCore
import AuraDesignSystem
import EventKit
import SwiftUI

/// Suite de AuraCalendar (AURA-015). Todo con dobles: NUNCA se solicita acceso ni se leen eventos reales.
/// Única lectura del sistema: `EKEventStore.authorizationStatus` (sin diálogo) y consultas de NSWorkspace que no abren nada.
/// Con `AURA_CALENDAR_RENDER_DIR=<ruta>` además genera PNG de CalendarView.

// MARK: - Dobles

private final class FakeAuth: CalendarAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: CalendarAuthStatus, _calls = 0
    var grant = true, blockFor: TimeInterval = 0
    init(_ s: CalendarAuthStatus) { _status = s }
    var current: CalendarAuthStatus { get { lock.lock(); defer { lock.unlock() }; return _status } set { lock.lock(); _status = newValue; lock.unlock() } }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    func status() -> CalendarAuthStatus { current }
    func requestAccess() async throws -> Bool {
        lock.withLock { _calls += 1 }
        if blockFor > 0 { try? await Task.sleep(for: .seconds(blockFor)) }  // simula la espera/bloqueo del sistema
        current = grant ? .authorized : .denied
        return grant
    }
}

private final class FakeSource: EventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [CalendarEvent] = [], _ranges: [(Date, Date)] = [], cont: AsyncStream<Void>.Continuation?
    var failure: String?
    var events: [CalendarEvent] { get { lock.lock(); defer { lock.unlock() }; return _events } set { lock.lock(); _events = newValue; lock.unlock() } }
    var ranges: [(Date, Date)] { lock.lock(); defer { lock.unlock() }; return _ranges }
    func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        let e = lock.withLock { _ranges.append((from, to)); return _events }
        if let failure { throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        return e
    }
    func changes() -> AsyncStream<Void> { AsyncStream { self.cont = $0 } }
    func fire() { cont?.yield() }
}

private final class FakeOpener: CalendarOpening, @unchecked Sendable {
    var settings = 0, app = 0
    func openPrivacySettings() { settings += 1 }
    func openCalendarApp() { app += 1 }
}

// MARK: - Utilidades

private func cal(_ tz: String = "Europe/Madrid") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!; c.locale = Locale(identifier: "es_ES"); return c
}

private func at(_ d: Int, _ h: Int, _ m: Int = 0, month: Int = 10, tz: String = "Europe/Madrid") -> Date {
    cal(tz).date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
}

private func ev(_ id: String, _ title: String, _ s: Date, _ e: Date, allDay: Bool = false, cal c: String = "Trabajo") -> CalendarEvent {
    CalendarEvent(id: id, title: title, start: s, end: e, isAllDay: allDay, calendarTitle: c, calendarColor: RGB(0.2, 0.6, 1))
}

@MainActor private func pump(_ seconds: Double = 0.1, until cond: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

/// Reloj mutable para las pruebas (el servicio recibe un cierre).
private final class Clock: @unchecked Sendable { var date: Date; init(_ d: Date) { date = d } }

@MainActor private func make(_ status: CalendarAuthStatus = .authorized, events: [CalendarEvent] = [], now: Date = at(24, 9),
                             tz: String = "Europe/Madrid", limit: Int = 10, timeout: Duration = .seconds(5),
                             center: NotificationCenter = NotificationCenter()) -> (CalendarService, FakeAuth, FakeSource, FakeOpener, Clock) {
    let a = FakeAuth(status), s = FakeSource(), o = FakeOpener(), c = Clock(now)
    s.events = events
    let svc = CalendarService(authorizer: a, source: s, opener: o, calendar: cal(tz), now: { c.date }, center: center,
                              limit: limit, debounce: .milliseconds(40), requestTimeout: timeout)
    return (svc, a, s, o, c)
}

// MARK: - Suite

@MainActor
func runCalendarSuite(_ t: SelfCheck) {
    realReadOnlyChecks(t)
    states(t)
    ordering(t)
    formatting(t)
    timeZoneAndDayChange(t)
    coalescence(t)
    permission(t)
    compact(t)
    if let dir = ProcessInfo.processInfo.environment["AURA_CALENDAR_RENDER_DIR"] { render(t, to: dir) }
}

/// Lecturas inocuas del sistema: no abren nada ni muestran diálogo.
@MainActor private func realReadOnlyChecks(_ t: SelfCheck) {
    let raw = EKEventStore.authorizationStatus(for: .event)
    print("INFO calendario: EKEventStore.authorizationStatus(.event) = \(raw.rawValue) (0 noDeterminado, 1 restringido, 2 denegado, 3 completo, 4 solo escritura)")
    t.expect(EventKitCalendar().status() == {
        switch raw { case .notDetermined: .notDetermined; case .fullAccess, .authorized: .authorized; case .writeOnly: .writeOnly
        case .restricted: .restricted; default: .denied } }(), "EventKitCalendar.status() refleja authorizationStatus sin diálogo")
    let handler = NSWorkspace.shared.urlForApplication(toOpen: SystemCalendarOpener.privacyURL)
    print("INFO calendario: manejador de x-apple.systempreferences = \(handler?.path ?? "ninguno")")
    t.expect(handler != nil, "la URL de Privacidad > Calendarios tiene manejador (no se abre)")
    let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SystemCalendarOpener.calendarBundleID)
    print("INFO calendario: app Calendario = \(app?.path ?? "ninguna")")
    t.expect(app != nil, "la app Calendario (com.apple.iCal) existe (no se abre)")
}

@MainActor private func states(_ t: SelfCheck) {
    // Sin start(): nada se carga.
    let (idle, _, idleSrc, _, _) = make(events: [ev("1", "A", at(24, 10), at(24, 11))])
    pump(0.1)
    t.expect(idle.state == .loading && idle.events.isEmpty && idleSrc.ranges.isEmpty, "sin start(): no carga nada")

    for (status, expected) in [(CalendarAuthStatus.notDetermined, CalendarState.notDetermined), (.denied, .denied),
                               (.restricted, .noPermission), (.writeOnly, .noPermission)] {
        let (s, _, src, _, _) = make(status); s.start(); pump(0.1)
        t.expect(s.state == expected && s.events.isEmpty && src.ranges.isEmpty, "estado \(status) -> \(expected) sin cargar")
    }

    let (ready, _, src, _, _) = make(events: [ev("1", "Reunión de equipo", at(24, 10), at(24, 11))])
    ready.start(); pump(1, until: { ready.state == .ready })
    t.expect(ready.state == .ready && ready.events.count == 1, "autorizado con eventos -> ready")
    if let r = src.ranges.first {
        t.expect(r.0 == at(24, 9), "ventana empieza ahora")
        t.expect(r.1 == at(31, 0), "ventana termina 7 días después de la medianoche de hoy (\(r.1))")
    }
    ready.stop()
    t.expect(ready.events.isEmpty && ready.state == .loading, "stop() olvida los eventos")

    let (empty, _, _, _, _) = make(); empty.start(); pump(1, until: { empty.state == .empty })
    t.expect(empty.state == .empty, "sin eventos -> empty")

    let (err, _, esrc, _, _) = make(); esrc.failure = "fallo de prueba"; err.start(); pump(1, until: { err.state != .loading })
    t.expect(err.state == .error("fallo de prueba"), "error de origen -> error")
    esrc.failure = nil; esrc.events = [ev("1", "A", at(24, 10), at(24, 11))]; err.reload(); pump(1, until: { err.state == .ready })
    t.expect(err.state == .ready, "reintento tras error -> ready")
    err.stop()

    // Estado denegado: explicación + botón de ajustes (el opener es un doble, no se abre nada).
    let (den, _, _, op, _) = make(.denied); den.start()
    den.openPrivacySettings()
    t.expect(op.settings == 1 && den.state == .denied, "denegado: botón abre Ajustes (doble)")
    let ev1 = ev("1", "A", at(24, 10), at(24, 11)); den.open(ev1)
    t.expect(op.app == 1, "abrir evento -> abrir Calendario")
    t.expect(SystemCalendarOpener.privacyURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars", "URL de Privacidad")
}

@MainActor private func ordering(_ t: SelfCheck) {
    let now = at(24, 9)
    let list = [
        ev("late", "Tarde", at(24, 18), at(24, 19)),
        ev("past", "Ya terminó", at(24, 7), at(24, 8)),
        ev("ongoing", "En curso", at(24, 8), at(24, 10)),
        ev("b", "b título", at(25, 9), at(25, 10)),
        ev("a", "A título", at(25, 9), at(25, 10)),
        ev("allday", "Festivo", at(25, 0), at(26, 0), allDay: true),
        ev("multi", "Viaje", at(23, 0), at(27, 0), allDay: true),
        ev("night", "Guardia", at(24, 23), at(25, 1)),
    ]
    let (s, _, _, _, _) = make(events: list, now: now); s.start(); pump(1, until: { s.state == .ready })
    t.expect(s.events.map(\.id) == ["multi", "ongoing", "late", "night", "allday", "a", "b"], "orden/filtrado: \(s.events.map(\.id))")
    let (lim, _, _, _, _) = make(events: list, now: now, limit: 3); lim.start(); pump(1, until: { lim.state == .ready })
    t.expect(lim.events.map(\.id) == ["multi", "ongoing", "late"], "límite N=3: \(lim.events.map(\.id))")
    // Calendarios y títulos vacíos.
    let blank = ev("x", "  ", at(24, 10), at(24, 11), cal: "")
    t.expect(s.displayTitle(blank) == "Sin título" && s.calendarName(blank) == "Calendario sin nombre", "títulos vacíos con respaldo")
    t.expect(s.accessibilityLabel(blank) == "Sin título, hoy de 10:00 a 11:00, calendario Calendario sin nombre", "etiqueta con respaldo: \(s.accessibilityLabel(blank))")
}

@MainActor private func formatting(_ t: SelfCheck) {
    let (s, _, _, _, _) = make(now: at(24, 9))
    t.expect(s.accessibilityLabel(ev("1", "Reunión de equipo", at(24, 10), at(24, 11))) == "Reunión de equipo, hoy de 10:00 a 11:00, calendario Trabajo", "VoiceOver: ejemplo del encargo")
    t.expect(s.when(ev("1", "x", at(25, 10), at(25, 11))) == "mañana de 10:00 a 11:00", "mañana")
    t.expect(s.when(ev("1", "x", at(24, 0), at(25, 0), allDay: true)) == "hoy, todo el día", "todo el día (fin exclusivo)")
    t.expect(s.when(ev("1", "x", at(24, 0), at(24, 23, 59), allDay: true)) == "hoy, todo el día", "todo el día (fin 23:59)")
    let multi = s.when(ev("1", "x", at(25, 0), at(28, 0), allDay: true))
    t.expect(multi.hasPrefix("del mañana al ") && multi.hasSuffix(", todo el día"), "multi-día: \(multi)")
    t.expect(s.when(ev("1", "x", at(24, 23), at(25, 1))) == "hoy desde las 23:00 hasta mañana a las 1:00", "cruce de medianoche: \(s.when(ev("1", "x", at(24, 23), at(25, 1))))")
    t.expect(s.when(ev("1", "x", at(24, 22), at(25, 0))) == "hoy de 22:00 a 0:00", "fin exacto a medianoche no es cruce")
    let far = s.when(ev("1", "x", at(28, 10), at(28, 11)))
    t.expect(far.contains("28") && far.hasSuffix("de 10:00 a 11:00"), "día lejano con fecha: \(far)")
}

@MainActor private func timeZoneAndDayChange(_ t: SelfCheck) {
    // El mismo instante (24 oct 23:30 en Madrid) es «mañana» en Tokio y «hoy» en Madrid.
    let e = ev("1", "Cena", at(24, 23, 30), at(25, 0, 30))
    let (mad, _, _, _, _) = make(now: at(24, 9), tz: "Europe/Madrid")
    let (tok, _, _, _, _) = make(now: at(24, 9), tz: "Asia/Tokyo")
    t.expect(mad.when(e).hasPrefix("hoy"), "Madrid: hoy (\(mad.when(e)))")
    t.expect(!tok.when(e).hasPrefix("hoy"), "Tokio: otro día (\(tok.when(e)))")

    // Cambio de día: tras la notificación y con el reloj en el día siguiente se recarga con la ventana nueva.
    let center = NotificationCenter()
    let (s, _, src, _, clock) = make(events: [ev("1", "Hoy", at(24, 23), at(24, 23, 30)), ev("2", "Mañana", at(25, 10), at(25, 11))],
                                     now: at(24, 22), center: center)
    s.start(); pump(1, until: { s.state == .ready })
    t.expect(s.events.count == 2, "antes de medianoche: 2 eventos")
    clock.date = at(25, 0, 5)
    center.post(name: .NSCalendarDayChanged, object: nil)
    pump(1, until: { src.ranges.count >= 2 })
    pump(0.2)
    t.expect(src.ranges.count == 2 && src.ranges[1].0 == at(25, 0, 5) && src.ranges[1].1 == at(1, 0, month: 11), "ventana nueva tras cambio de día")
    t.expect(s.events.map(\.id) == ["2"], "tras cambio de día solo queda «Mañana»: \(s.events.map(\.id))")
    t.expect(s.when(s.events[0]).hasPrefix("hoy"), "ahora es «hoy»")
    // Cambio de zona horaria: otra notificación, otra recarga.
    center.post(name: .NSSystemTimeZoneDidChange, object: nil); pump(0.3, until: { src.ranges.count >= 3 })
    t.expect(src.ranges.count == 3, "cambio de zona recarga")
    s.stop()
    center.post(name: .NSCalendarDayChanged, object: nil); pump(0.2)
    t.expect(src.ranges.count == 3, "tras stop() las notificaciones no recargan")
}

@MainActor private func coalescence(_ t: SelfCheck) {
    let (s, _, src, _, _) = make(events: [ev("1", "A", at(24, 10), at(24, 11))])
    s.start(); pump(1, until: { s.state == .ready })
    let before = src.ranges.count
    for _ in 0..<20 { src.fire() }
    pump(0.5, until: { src.ranges.count > before })
    pump(0.2)
    t.expect(src.ranges.count == before + 1, "20 cambios de almacén -> 1 recarga (\(src.ranges.count - before))")
    src.events = [ev("1", "A", at(24, 10), at(24, 11)), ev("2", "B", at(24, 12), at(24, 13))]
    src.fire(); pump(1, until: { s.events.count == 2 })
    t.expect(s.events.count == 2, "el cambio refleja el evento nuevo")
    // Sin cambio de contenido, no se invalida la vista.
    let rev = s.renderRevision; src.fire(); pump(0.4)
    t.expect(s.renderRevision == rev, "recarga idéntica no cambia lo observable")
    s.stop()
    let afterStop = src.ranges.count
    src.fire(); pump(0.3)
    t.expect(src.ranges.count == afterStop, "tras stop() los cambios no recargan")
}

@MainActor private func permission(_ t: SelfCheck) {
    // Nunca se solicita al arrancar ni al abrir el módulo.
    let (s, auth, _, _, _) = make(.notDetermined); s.start(); s.refreshAuthorization(); pump(0.2)
    t.expect(auth.calls == 0 && s.state == .notDetermined, "arrancar no solicita permiso")

    // Concedido: tras el botón carga eventos.
    let (g, ga, gsrc, _, _) = make(.notDetermined, events: [ev("1", "A", at(24, 10), at(24, 11))]); g.start()
    Task { await g.requestAccess() }
    pump(2, until: { g.state == .ready })
    t.expect(ga.calls == 1 && g.state == .ready && !gsrc.ranges.isEmpty, "solicitud concedida -> carga")

    // Denegado por el usuario.
    let (d, da, _, _, _) = make(.notDetermined); da.grant = false; d.start()
    Task { await d.requestAccess() }; pump(2, until: { d.state == .denied })
    t.expect(d.state == .denied && !d.isRequesting, "solicitud denegada -> denied")

    // Sin apilar + timeout propio: el sistema se bloquea 1,5 s, el timeout es 0,2 s.
    let (b, ba, _, _, _) = make(.notDetermined, events: [ev("1", "A", at(24, 10), at(24, 11))], timeout: .milliseconds(200))
    ba.blockFor = 1.5; b.start()
    var returned = 0
    let t0 = Date()
    for _ in 0..<3 { Task { await b.requestAccess(); returned += 1 } }
    pump(1, until: { returned == 3 })
    t.expect(returned == 3 && Date().timeIntervalSince(t0) < 1.2, "timeout propio libera la UI (<1,2 s)")
    t.expect(ba.calls == 1, "3 pulsaciones -> 1 sola llamada al sistema (\(ba.calls))")
    t.expect(!b.isRequesting && b.notice != nil && b.state == .notDetermined, "tras timeout: aviso y sin esperar")
    Task { await b.requestAccess() }; pump(0.3)
    t.expect(ba.calls == 1, "reintento con la llamada aún viva no apila")
    pump(3, until: { b.state == .ready })
    t.expect(b.state == .ready && b.notice == nil, "cuando el sistema responde tarde se aplica el resultado")

    // Si ya está concedido o denegado, requestAccess no llama al sistema.
    let (x, xa, _, _, _) = make(.denied); x.start()
    Task { await x.requestAccess() }; pump(0.2)
    t.expect(xa.calls == 0, "denegado: no se vuelve a solicitar")
}

@MainActor private func compact(_ t: SelfCheck) {
    let now = at(24, 9)
    let (s, _, _, _, _) = make(events: [ev("far", "Más tarde", at(24, 12), at(24, 13)), ev("day", "Festivo", at(24, 0), at(25, 0), allDay: true)], now: now)
    s.start(); pump(1, until: { s.state == .ready })
    t.expect(s.compactInfo() == nil, "Quiet by default: nada inminente -> nil")
    let (n, _, _, _, _) = make(events: [ev("soon", "Reunión de equipo semanal", at(24, 9, 12), at(24, 10))], now: now)
    n.start(); pump(1, until: { n.state == .ready })
    let info = n.compactInfo()
    t.expect(info?.detail == "Reunión de equip… en 12 min", "texto breve: \(info?.detail ?? "nil")")
    t.expect(info?.accessibilityLabel == "Reunión de equipo semanal empieza en 12 minutos", "etiqueta: \(info?.accessibilityLabel ?? "nil")")
    t.expect(n.compactInfo(at: at(24, 9, 20)) == nil, "ya empezó -> nil")
    t.expect(n.compactInfo(at: at(24, 8, 40)) == nil, "faltan >15 min -> nil")
}

// MARK: - Render

@MainActor private func render(_ t: SelfCheck, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func shot(_ name: String, _ s: CalendarService, height: CGFloat = 230) {
        let v = CalendarView(service: s).frame(width: 520, height: height).background(Color.black).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = host; win.appearance = NSAppearance(named: .darkAqua)
        pump(0.3)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { t.expect(false, "sin bitmap \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { t.expect(false, "sin PNG \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    let sample = [
        ev("1", "Reunión de equipo", at(24, 10), at(24, 11)),
        ev("2", "Guardia nocturna", at(24, 23), at(25, 1), cal: "Guardias"),
        ev("3", "Viaje a Lisboa con un título muy largo que no cabe en una línea del panel", at(25, 0), at(27, 0), allDay: true, cal: "Personal"),
        ev("4", "", at(26, 9), at(26, 9, 30), cal: ""),
    ]
    func run(_ status: CalendarAuthStatus, _ events: [CalendarEvent] = [], wait: (CalendarService) -> Bool = { _ in true }) -> CalendarService {
        let (s, _, _, _, _) = make(status, events: events); s.start(); pump(1) ; _ = wait(s); return s
    }
    shot("calendar-loading", make().0)
    shot("calendar-not-determined", run(.notDetermined))
    shot("calendar-denied", run(.denied))
    shot("calendar-restricted", run(.restricted))
    shot("calendar-empty", run(.authorized))
    shot("calendar-ready", run(.authorized, sample), height: 260)
    let (err, _, esrc, _, _) = make(); esrc.failure = "El almacén de calendarios no respondió."; err.start(); pump(0.5)
    shot("calendar-error", err)
    let (req, ra, _, _, _) = make(.notDetermined, timeout: .seconds(5)); ra.blockFor = 1; req.start()
    Task { await req.requestAccess() }; pump(0.2)
    shot("calendar-requesting", req)
    let (to, ta, _, _, _) = make(.notDetermined, timeout: .milliseconds(100)); ta.blockFor = 1; to.start()
    Task { await to.requestAccess() }; pump(0.4)
    shot("calendar-timeout-notice", to)
    pump(1.5)
}
