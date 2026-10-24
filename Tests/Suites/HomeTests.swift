import AppKit
import AuraCalendar
import AuraCore
import AuraDesignSystem
import AuraHome
import AuraMedia
import AuraPreferences
import AuraShelf
import AuraWidgets
import SwiftUI

/// Suite de AuraHome (Inicio + Onboarding). Todo con dobles: no se piden permisos ni se leen datos reales.
/// Con `AURA_HOME_RENDER_DIR=<ruta>` además genera PNG (NSHostingView en ventana fuera de pantalla).

// MARK: - Dobles

private final class HProvider: MediaProvider, @unchecked Sendable {
    let id = "music"
    var capabilities: MediaCapabilities
    private var cont: AsyncStream<MediaItem?>.Continuation?
    init(caps: MediaCapabilities = [.play, .pause, .skip, .openSource]) { capabilities = caps }
    var authorizationState: AuthorizationState { get async { .authorized } }
    var currentItem: MediaItem? { get async { nil } }
    func play() async throws {}
    func pause() async throws {}
    func skip(forward: Bool) async throws {}
    func seek(to position: TimeInterval) async throws {}
    func observe() -> AsyncStream<MediaItem?> { AsyncStream { self.cont = $0 } }
    func send(_ i: MediaItem?) { cont?.yield(i) }
}

private final class HAuth: CalendarAuthorizing, @unchecked Sendable {
    let s: CalendarAuthStatus; var calls = 0
    init(_ s: CalendarAuthStatus) { self.s = s }
    func status() -> CalendarAuthStatus { s }
    func requestAccess() async throws -> Bool { calls += 1; return true }
}
private final class HSource: EventSource, @unchecked Sendable {
    var events: [CalendarEvent] = []
    func events(from: Date, to: Date) async throws -> [CalendarEvent] { events }
    func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
}
private final class HOpener: CalendarOpening, @unchecked Sendable {
    func openPrivacySettings() {}
    func openCalendarApp() {}
}
@MainActor private final class HPower: PowerSource {
    var r: PowerReading
    init(_ r: PowerReading) { self.r = r }
    func read() throws -> PowerReading { r }
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void { {} }
}

@MainActor private func pump(_ seconds: Double = 0.1, until cond: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func freshDefaults() -> UserDefaults {
    let name = "aura.test.home.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

private let t0 = Date(timeIntervalSince1970: 1_792_000_000)  // instante fijo para pruebas y capturas

// MARK: - Suite

@MainActor func runHomeSuite(_ t: SelfCheck) {
    selection(t)
    onboarding(t)
    services(t)
    if let dir = ProcessInfo.processInfo.environment["AURA_HOME_RENDER_DIR"] { render(t, to: dir) }
}

@MainActor private func selection(_ t: SelfCheck) {
    var i = HomeInputs()
    t.expect(HomeModel.cards(i).isEmpty, "nada → sin tarjetas (estado vacío)")
    i.shelfCount = 0; i.battery = BatteryGlimpse(percent: 80, isCharging: false, isLow: false)
    t.expect(HomeModel.cards(i).isEmpty, "batería normal → no aparece")
    i.battery = BatteryGlimpse(percent: 100, isCharging: true, isCharged: true, isLow: false)
    t.expect(HomeModel.cards(i).isEmpty, "batería cargada → no aparece")
    i.battery = BatteryGlimpse(percent: 12, isCharging: false, isLow: true)
    t.expect(HomeModel.cards(i).isEmpty, "batería baja → va en la cabecera, no es tarjeta")
    i.battery = nil
    i.clipboardCount = 2
    t.expect(HomeModel.cards(i) == [.clipboard], "portapapeles con elementos → tarjeta; vacío no (más abajo)")
    i.clipboardCount = 0
    t.expect(HomeModel.cards(i).isEmpty, "portapapeles vacío → sin tarjeta")

    // Módulos activos: su tarjeta se muestra siempre (con texto de estado si no hay contenido), en orden fijo.
    var k = HomeInputs()
    k.calendarEnabled = true; k.shelfEnabled = true; k.clipboardEnabled = true
    t.expect(HomeModel.cards(k) == [.event, .clipboard, .shelf], "módulos activos y vacíos → tarjetas con estado vacío")
    k.shelfEnabled = false
    t.expect(HomeModel.cards(k) == [.event, .clipboard], "módulo desactivado → sin tarjeta")

    var j = HomeInputs()
    j.timer = .running(end: t0); j.hasNowPlaying = true
    t.expect(HomeModel.cards(j) == [.timer, .media], "timer + media en orden de relevancia")
    j.timer = .paused(remaining: 30)
    t.expect(HomeModel.cards(j).first == .timer, "timer en pausa sigue siendo tarjeta")
    j.timer = .finished
    t.expect(HomeModel.cards(j).first == .timer, "timer terminado visible")
    j.timer = .idle
    t.expect(HomeModel.cards(j) == [.media], "timer idle → no aparece")
    j.hasUpcomingEvent = true; j.shelfCount = 3
    j.battery = BatteryGlimpse(percent: 5, isCharging: false, isLow: true)
    j.timer = .running(end: t0)
    j.clipboardCount = 1
    t.expect(HomeModel.cards(j) == [.timer, .media, .event, .clipboard, .shelf], "todas, orden fijo")

    // Calendario: solo con servicio ya listo; sin permiso o cargando no aparece.
    let ev = CalendarEvent(id: "1", title: "Reunión", start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(1800), calendarTitle: "Trabajo")
    let past = CalendarEvent(id: "0", title: "Pasado", start: t0.addingTimeInterval(-3600), end: t0.addingTimeInterval(-60), calendarTitle: "Trabajo")
    for s in [CalendarState.loading, .noPermission, .notDetermined, .denied, .empty, .error("x")] {
        t.expect(HomeModel.nextEvent(state: s, events: [ev], now: t0) == nil, "calendario \(s) → sin evento")
    }
    t.expect(HomeModel.nextEvent(state: .ready, events: [past, ev], now: t0)?.id == "1", "salta eventos terminados")
    t.expect(HomeModel.nextEvent(state: .ready, events: [past], now: t0) == nil, "solo pasados → nada")

    // Eventos de hoy: sin terminar y antes de mañana, los de todo el día primero, máximo 3.
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
    func at(_ h: Int, day: Int = 24) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))! }
    func e(_ id: String, _ s: Date, _ en: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: s, end: en, isAllDay: allDay, calendarTitle: "T")
    }
    let evs = [e("tarde", at(18), at(19)), e("mañana-ya", at(9), at(10)), e("ahora", at(11), at(13)), e("sig-dia", at(9, day: 25), at(10, day: 25)),
               e("todo", at(0), at(23), allDay: true), e("noche", at(21), at(22)), e("extra", at(20), at(20))]
    let today = HomeModel.todayEvents(state: .ready, events: evs, now: noon, calendar: cal)
    t.expect(today.map(\.id) == ["todo", "ahora", "tarde"], "hoy: todo el día primero, sin pasados ni de mañana, máx. 3 (\(today.map(\.id)))")
    t.expect(HomeModel.todayEvents(state: .loading, events: evs, now: noon, calendar: cal).isEmpty, "hoy: sin calendario listo no hay eventos")

    t.expect(HomeModel.greeting(hour: 8) == .morning && HomeModel.greeting(hour: 15) == .afternoon
             && HomeModel.greeting(hour: 23) == .evening && HomeModel.greeting(hour: 3) == .evening, "saludo por hora")
    t.expect(HomeModel.clock(300) == "5:00" && HomeModel.clock(0.2) == "0:01" && HomeModel.clock(3725) == "1:02:05"
             && HomeModel.clock(-4) == "0:00", "formato de reloj")
    t.expect(HomeModel.spoken(125) == "2 minutos 5 segundos" && HomeModel.spoken(3600) == "1 hora", "texto hablado")
}

@MainActor private func onboarding(_ t: SelfCheck) {
    let d = freshDefaults()
    let s = OnboardingState(defaults: d)
    t.expect(s.shouldShow && !s.isDone, "primera vez → se muestra")
    t.expect(OnboardingState.key == "aura.onboarding.done", "clave estable")
    s.markDone()
    t.expect(!s.shouldShow && d.bool(forKey: "aura.onboarding.done"), "tras omitir/completar → no se muestra")
    t.expect(!OnboardingState(defaults: d).shouldShow, "persiste entre instancias (retorno)")
    s.reset()
    t.expect(s.shouldShow, "reset → primera vez")

    t.expect(OnboardingStep.welcome.next == .privacy && OnboardingStep.privacy.next == .modules
             && OnboardingStep.modules.isLast && OnboardingStep.welcome.previous == nil, "pasos")

    // Módulos desactivados: la escritura llega al SettingsStore real (con UserDefaults aislado).
    let store = SettingsStore(defaults: freshDefaults())
    t.expect(store.settings.disabledModules == [.clipboard], "por defecto todo activo salvo el portapapeles")
    store.setModule(.calendar, enabled: false)
    store.setModule(.media, enabled: false)
    t.expect(store.settings.disabledModules == [.clipboard, .calendar, .media], "desactivar escribe disabledModules")
    store.setModule(.calendar, enabled: true)
    t.expect(store.settings.disabledModules == [.clipboard, .media], "reactivar lo quita")
    store.flush()
}

@MainActor private func services(_ t: SelfCheck) {
    let timer = TimerService(clock: { t0 }, duration: 60)
    let shelf = ShelfService()
    let bat = BatteryService(source: HPower(PowerReading(hasBattery: true, percent: 10, isCharging: false, isPluggedIn: false)))
    bat.refresh()
    let auth = HAuth(.notDetermined)
    let cal = CalendarService(authorizer: auth, source: HSource(), opener: HOpener(), now: { t0 })
    let none = HomeInputs(media: nil, timer: nil, calendar: nil, shelf: nil, battery: nil, now: t0)
    t.expect(none == HomeInputs(), "servicios ausentes → entradas neutras")
    timer.start()
    var i = HomeInputs(media: nil, timer: timer, calendar: cal, shelf: shelf, battery: bat, now: t0)
    t.expect(i.timer == timer.phase && i.battery?.isLow == true, "lectura de timer y batería baja")
    t.expect(!i.hasUpcomingEvent && auth.calls == 0, "calendario sin cargar: no aparece y NO se pide acceso")
    timer.cancel()
    i = HomeInputs(media: nil, timer: timer, calendar: nil, shelf: nil, battery: nil, now: t0)
    t.expect(HomeModel.cards(i).isEmpty, "timer cancelado → vacío")

    let p = HProvider()
    let media = MediaService(providers: [p]); media.start()
    pump(0.2)  // deja arrancar la tarea que escucha al proveedor
    t.expect(!HomeInputs(media: media, timer: nil, calendar: nil, shelf: nil, battery: nil, now: t0).hasNowPlaying, "sin reproductor → no aparece")
    p.send(MediaItem(title: "So What", artist: "Miles Davis", isPlaying: true))
    pump(0.3, until: { media.current != nil })
    t.expect(HomeInputs(media: media, timer: nil, calendar: nil, shelf: nil, battery: nil, now: t0).hasNowPlaying, "suena → aparece")
    media.stop()
}

// MARK: - Capturas

@MainActor private func render(_ t: SelfCheck, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func shot<V: View>(_ name: String, _ v: V, _ w: CGFloat, _ h: CGFloat) {
        let host = NSHostingView(rootView: v.frame(width: w, height: h).background(Color.black).environment(\.colorScheme, .dark))
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
    let date = Date(timeIntervalSince1970: 1_792_000_000 - 3 * 3600)
    func home(_ name: String, media: MediaService? = nil, timer: TimerService? = nil, calendar: CalendarService? = nil,
              shelf: ShelfService? = nil, battery: BatteryService? = nil) {
        shot(name, HomeView(media: media, timer: timer, calendar: calendar, shelf: shelf, battery: battery, now: { date }, onNavigate: { _ in })
            .padding(Space.lg), 520, 200)
    }
    // Vacío y cargando
    home("home-empty")
    home("home-empty-all-services", media: nil, timer: TimerService(clock: { date }), shelf: ShelfService())
    home("home-loading", media: MediaService(providers: [HProvider()]))

    // Con contenido
    let timer = TimerService(clock: { date }, duration: 300); timer.start()
    let p = HProvider(caps: [.play, .pause, .skip, .seek, .openSource])
    let media = MediaService(providers: [p]); media.start()
    pump(0.2)  // deja arrancar la tarea que escucha al proveedor
    p.send(MediaItem(title: "So What", artist: "Miles Davis", duration: 562, isPlaying: true))
    pump(0.3, until: { media.current != nil })
    Task { await media.refreshAuthorization() }  // como haría el módulo Medios al mostrarse: aporta las capacidades
    pump(0.3)
    home("home-timer-media", media: media, timer: timer)
    home("home-media-only", media: media)

    let src = HSource()
    src.events = [CalendarEvent(id: "e", title: "Reunión de equipo", start: date.addingTimeInterval(1800), end: date.addingTimeInterval(5400), calendarTitle: "Trabajo")]
    let cal = CalendarService(authorizer: HAuth(.authorized), source: src, opener: HOpener(), now: { date }); cal.start()
    pump(0.6, until: { cal.state == .ready })
    let shelf = ShelfService()
    _ = shelf.add(urls: [URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/etc/paths")])
    let bat = BatteryService(source: HPower(PowerReading(hasBattery: true, percent: 14, isCharging: false, isPluggedIn: false)))
    bat.refresh()
    home("home-full", media: media, timer: timer, calendar: cal, shelf: shelf, battery: bat)
    let paused = TimerService(clock: { date }, duration: 90); paused.start(); paused.pause()
    home("home-timer-paused-shelf", timer: paused, shelf: shelf)
    let chg = BatteryService(source: HPower(PowerReading(hasBattery: true, percent: 55, isCharging: true, isPluggedIn: true)))
    chg.refresh()
    home("home-battery-charging", battery: chg)
    media.stop(); cal.stop()

    // Onboarding (store aislado)
    for step in OnboardingStep.allCases {
        shot("onboarding-\(step)", OnboardingView(store: SettingsStore(defaults: freshDefaults()), initialStep: step, onFinish: {}), 520, 440)
    }
    let st = SettingsStore(defaults: freshDefaults()); st.setModule(.calendar, enabled: false)
    shot("onboarding-modules-calendar-off", OnboardingView(store: st, initialStep: .modules, onFinish: {}), 520, 440)
    shot("onboarding-returning", OnboardingView(store: SettingsStore(defaults: freshDefaults()), isReturning: true, onFinish: {}), 520, 440)
}
