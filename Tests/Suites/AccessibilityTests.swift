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

// Suite de accesibilidad. Auditoría AUTOMÁTICA del árbol que AppKit
// expone para las vistas reales, montadas en NSWindow fuera de pantalla con dobles.
//
// QUÉ VERIFICA: nombres, roles, valores, estado seleccionado/habilitado, acciones, estados vacíos/error
// y participación en el anillo de foco de teclado (proxies KeyViewProxy), todo leído del árbol de AppKit.
// QUÉ NO VERIFICA: VoiceOver real (orden de lectura, anuncios, navegación), Tab/Full Keyboard Access real,
// flechas de ModuleNavBar, ni el aspecto visual. Los casos «FINDING:» son defectos reproducibles en
// producción y NO se relajan: su fallo es el hallazgo documentado para el LEAD.

// MARK: - Acceso al árbol de AppKit
// SwiftUI expone `AccessibilityNode` (no NSView) y los miembros NSAccessibility de esos nodos no son
// importables como miembros Swift: se leen por selector con IMP tipados (solo retornos objeto o BOOL).
// AppKit solo materializa ese árbol con `finishLaunching` + app activa: sin ello `accessibilityChildren`
// devuelve [] en todos los casos probados (ventana fuera de pantalla, visible, clave o alfa 0).

private typealias AXObjFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
private typealias AXBoolFn = @convention(c) (AnyObject, Selector) -> ObjCBool

@MainActor private func axObj(_ o: AnyObject, _ name: String) -> AnyObject? {
    let s = NSSelectorFromString(name)
    guard o.responds(to: s), let imp = o.method(for: s) else { return nil }
    return unsafeBitCast(imp, to: AXObjFn.self)(o, s)?.takeUnretainedValue()
}

@MainActor private func axFlag(_ o: AnyObject, _ name: String) -> Bool? {
    let s = NSSelectorFromString(name)
    guard o.responds(to: s), let imp = o.method(for: s) else { return nil }
    return unsafeBitCast(imp, to: AXBoolFn.self)(o, s).boolValue
}

@MainActor private func axStr(_ o: AnyObject, _ name: String) -> String? {
    guard let v = axObj(o, name) else { return nil }
    return (v as? String) ?? String(describing: v)
}

/// Atributo por la vía de atributos (cuando el selector directo no existe en el nodo).
@MainActor private func axAttr(_ o: AnyObject, _ a: NSAccessibility.Attribute) -> Any? {
    (o as? NSObject)?.accessibilityAttributeValue(a)
}

/// `accessibilityActionNames` no existe en todos los objetos (p. ej. NSSplitViewSplitter): se comprueba antes.
@MainActor private func axActionNames(_ o: AnyObject) -> [String] {
    guard let ob = o as? NSObject, ob.responds(to: NSSelectorFromString("accessibilityActionNames")) else { return [] }
    return ob.accessibilityActionNames().map { $0.rawValue }
}

/// Nodo del árbol de accesibilidad ya leído.
struct AXNode {
    let cls: String
    let role: String
    let label: String?
    let title: String?
    let value: String?
    let help: String?
    let isElement: Bool
    let enabled: Bool
    let selected: Bool
    let pressable: Bool
    let actions: [String]
    var children: [AXNode]

    /// Todos los nodos (preorden).
    var all: [AXNode] { [self] + children.flatMap(\.all) }
    /// Nombre accesible del control: etiqueta, o título si no hay etiqueta.
    var name: String { [label, title].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
    /// Texto mostrado (estáticos y encabezados llevan el texto en valor o etiqueta).
    var text: String { [label, value, title].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
}

@MainActor private func axRead(_ o: AnyObject, depth: Int) -> AXNode {
    // Si el objeto no declara hijos (nil), se baja por el atributo de hijos y luego por subvistas.
    var kids: [AnyObject] = []
    if depth < 40 {
        if let c = axObj(o, "accessibilityChildren") as? [AnyObject] { kids = c }
        else if let ob = o as? NSObject, let c = ob.accessibilityAttributeValue(NSAccessibility.Attribute.children) as? [AnyObject] { kids = c }
        else if let v = o as? NSView { kids = v.subviews }
    }
    let role = axStr(o, "accessibilityRole") ?? (axAttr(o, .role) as? String) ?? "-"
    let label = axStr(o, "accessibilityLabel") ?? (axAttr(o, .description) as? String)
    return AXNode(cls: String(describing: type(of: o)), role: role, label: label,
                  title: axStr(o, "accessibilityTitle"), value: axStr(o, "accessibilityValue"),
                  help: axStr(o, "accessibilityHelp"),
                  isElement: axFlag(o, "isAccessibilityElement") ?? false,
                  enabled: axFlag(o, "isAccessibilityEnabled") ?? false,
                  selected: axFlag(o, "isAccessibilitySelected") ?? (axAttr(o, .selected) as? Bool) ?? false,
                  pressable: o.responds(to: NSSelectorFromString("accessibilityPerformPress")),
                  actions: axActionNames(o) + ((axObj(o, "accessibilityCustomActions") as? [AnyObject]) ?? []).compactMap { axStr($0, "name") },
                  children: kids.map { axRead($0, depth: depth + 1) })
}

/// Vista montada fuera de pantalla con su árbol ya leído.
@MainActor private final class AXMount {
    let win: NSWindow
    let host: NSView
    let root: AXNode
    init(win: NSWindow, host: NSView, root: AXNode) { self.win = win; self.host = host; self.root = root }
    /// Subvistas `KeyViewProxy` (recursivo): SwiftUI las usa para el anillo de foco de teclado.
    var keyProxies: Int { AXMount.countProxies(host) }
    private static func countProxies(_ v: NSView) -> Int {
        v.subviews.reduce(0) { $0 + (String(describing: type(of: $1)) == "KeyViewProxy" ? 1 : 0) + countProxies($1) }
    }
}

@MainActor private var axKeepAlive: [NSWindow] = []

@MainActor private func axBootstrap() {
    NSApplication.shared.finishLaunching()
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor private func axPump(_ seconds: Double = 0.1, until cond: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

/// Monta `v` en una NSWindow fuera de pantalla, fuerza layout y lee el árbol.
@MainActor private func axMount<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat) -> AXMount {
    let host = NSHostingView(rootView: AnyView(v.frame(width: w, height: h)))
    host.frame = NSRect(x: 0, y: 0, width: w, height: h)
    let win = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: w, height: h),
                       styleMask: [.borderless], backing: .buffered, defer: true)
    win.contentView = host
    axKeepAlive.append(win)
    win.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    axPump(0.3)
    host.layoutSubtreeIfNeeded()
    return AXMount(win: win, host: host, root: axRead(host, depth: 0))
}

// MARK: - Dobles (privados, prefijo A11y)

private final class A11yClock: @unchecked Sendable { var now: Date; init(_ d: Date) { now = d } }

private final class A11yMediaProvider: MediaAuthorizing, @unchecked Sendable {
    let id: String
    var capabilities: MediaCapabilities
    var auth: AuthorizationState
    /// `hang`: la consulta de Automation no responde (la vista se queda en «cargando»).
    var hang = false
    private var cont: AsyncStream<MediaItem?>.Continuation?
    init(_ id: String = "music", caps: MediaCapabilities = [.play, .pause, .skip, .openSource], auth: AuthorizationState = .authorized) {
        self.id = id; capabilities = caps; self.auth = auth
    }
    var authorizationState: AuthorizationState {
        get async {
            if hang { try? await Task.sleep(for: .seconds(60)) }
            return auth
        }
    }
    var currentItem: MediaItem? { get async { nil } }
    func play() async throws {}
    func pause() async throws {}
    func skip(forward: Bool) async throws {}
    func seek(to p: TimeInterval) async throws {}
    func requestAuthorization() async throws -> AuthorizationState { auth = .authorized; return .authorized }
    func observe() -> AsyncStream<MediaItem?> { AsyncStream { self.cont = $0 } }
    func send(_ i: MediaItem?) { cont?.yield(i) }
}

@MainActor private final class A11yPower: PowerSource {
    var reading: PowerReading
    var fail = false
    init(_ r: PowerReading) { reading = r }
    func read() throws -> PowerReading {
        if fail { throw PowerError.unavailable }
        return reading
    }
    func observe(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void { { } }
}

private final class A11yCalAuth: CalendarAuthorizing, @unchecked Sendable {
    var current: CalendarAuthStatus
    init(_ s: CalendarAuthStatus) { current = s }
    func status() -> CalendarAuthStatus { current }
    func requestAccess() async throws -> Bool { current = .authorized; return true }
}

private final class A11yCalSource: EventSource, @unchecked Sendable {
    var events: [CalendarEvent] = []
    var failure: String?
    func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        if let failure { throw NSError(domain: "aura.a11y", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        return events
    }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private final class A11yCalOpener: CalendarOpening, @unchecked Sendable {
    func openPrivacySettings() {}
    func openCalendarApp() {}
}

private func a11yCal() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!; c.locale = Locale(identifier: "es_ES"); return c
}

private func a11yAt(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
    a11yCal().date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
}

@MainActor private func a11yFreshDefaults() -> UserDefaults {
    let name = "aura.a11y.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

/// Instante fijo para Inicio, temporizadores y calendario (mediodía, 24 oct 2026, Madrid).
private let a11yNow = a11yAt(24, 12)

@MainActor private func a11yCalService(_ status: CalendarAuthStatus, events: [CalendarEvent] = [], failure: String? = nil,
                                       ready: Bool = true) -> CalendarService {
    let src = A11yCalSource(); src.events = events; src.failure = failure
    let s = CalendarService(authorizer: A11yCalAuth(status), source: src, opener: A11yCalOpener(), calendar: a11yCal(),
                            now: { a11yNow }, center: NotificationCenter(), debounce: .milliseconds(40), requestTimeout: .seconds(5))
    if ready {
        s.start()
        axPump(1.0) { s.state != .loading }
    }
    return s
}

@MainActor private func a11yMediaService(_ providers: [A11yMediaProvider], item: MediaItem? = nil) -> MediaService {
    let s = MediaService(providers: providers)
    s.start()
    axPump(0.3)  // el observe() de cada proveedor debe estar suscrito antes de emitir
    if let item, let p = providers.first { p.send(item); axPump(0.4) { s.current != nil } }
    return s
}

private func a11yTempFiles(_ names: [String]) -> [URL] {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aura-a11y-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return names.map { n in
        let u = dir.appendingPathComponent(n)
        try? "x".data(using: .utf8)!.write(to: u)
        return u
    }
}

// MARK: - Pantallas

/// Todas las pantallas auditadas, por nombre estable.
@MainActor private func a11yScreens() -> [String: AXMount] {
    var out: [String: AXMount] = [:]
    func add<V: View>(_ name: String, _ v: V, _ w: CGFloat, _ h: CGFloat) { out[name] = axMount(v, w, h) }

    // Diseño (AuraDesignSystem)
    add("nav-home", ModuleNavBar(selection: .home, onSelect: { _ in }).padding(8), 300, 60)
    add("chrome-home", ExpandedChrome(module: .home, onSelect: { _ in }, onOpenSettings: {}) { Text("contenido") }, 520, 220)
    add("compact-media-playing", CompactContent(activity: .media(playing: true), detail: "3:20", centerGap: 60), 300, 32)
    add("compact-media-paused", CompactContent(activity: .media(playing: false), detail: "Título", centerGap: 60), 300, 32)
    add("compact-error", CompactContent(activity: .error, detail: "Fallo", centerGap: 60), 300, 32)
    add("compact-idle", CompactContent(activity: nil, centerGap: 60), 300, 32)

    // Inicio
    let dateNow = { a11yNow }
    add("home-quiet", HomeView(now: dateNow, onNavigate: { _ in }), 520, 200)
    let hanging = A11yMediaProvider(); hanging.hang = true
    add("home-loading", HomeView(media: MediaService(providers: [hanging]), now: dateNow, onNavigate: { _ in }), 520, 200)
    let clock = A11yClock(a11yNow)
    let running = TimerService(clock: { clock.now }, duration: 300); running.start()
    add("home-timer-running", HomeView(timer: running, now: dateNow, onNavigate: { _ in }), 520, 200)
    let paused = TimerService(clock: { clock.now }, duration: 300); paused.start(); paused.pause()
    add("home-timer-paused", HomeView(timer: paused, now: dateNow, onNavigate: { _ in }), 520, 200)
    let done = TimerService(clock: { clock.now }, duration: 60); done.start()
    clock.now = a11yNow.addingTimeInterval(120); done.refresh()
    add("home-timer-finished", HomeView(timer: done, now: dateNow, onNavigate: { _ in }), 520, 200)
    let mediaHome = a11yMediaService([A11yMediaProvider()], item: MediaItem(title: "So What", artist: "Miles Davis", duration: 200, position: 10, isPlaying: true))
    add("home-media", HomeView(media: mediaHome, now: dateNow, onNavigate: { _ in }), 520, 200)
    let cal = a11yCalService(.authorized, events: [CalendarEvent(id: "e1", title: "Reunión de equipo", start: a11yAt(24, 13), end: a11yAt(24, 14), calendarTitle: "Trabajo")])
    add("home-event", HomeView(calendar: cal, now: dateNow, onNavigate: { _ in }), 520, 200)
    let shelfHome = ShelfService()
    _ = shelfHome.add(urls: a11yTempFiles(["a.pdf", "b.png"]))
    add("home-shelf", HomeView(shelf: shelfHome, now: dateNow, onNavigate: { _ in }), 520, 200)
    let battery = BatteryService(source: A11yPower(PowerReading(hasBattery: true, percent: 12, isCharging: false, isPluggedIn: false)), center: NotificationCenter())
    battery.refresh(); axPump(0.2) { battery.state == .ready }
    add("home-battery-low", HomeView(battery: battery, now: dateNow, onNavigate: { _ in }), 520, 200)

    // Estantería
    add("shelf-empty", ShelfView(service: ShelfService()), 520, 190)
    let busy = ShelfService()
    _ = busy.add(urls: a11yTempFiles(["Informe.pdf", "foto.png"]) + [URL(string: "https://example.com/articulo")!])
    add("shelf-busy", ShelfView(service: busy), 520, 190)
    let corrupt = ShelfService(); corrupt.loadIssue = .corrupt
    add("shelf-corrupt", ShelfView(service: corrupt), 520, 190)
    let missingURL = a11yTempFiles(["desaparecido.txt"])[0]
    let missing = ShelfService()
    _ = missing.add(urls: [missingURL])
    axPump(0.3)
    try? FileManager.default.removeItem(at: missingURL)
    missing.refresh()
    axPump(3) { missing.items.first.map { missing.state(of: $0.id) == .missing } ?? false }
    add("shelf-missing", ShelfView(service: missing), 520, 190)

    // Multimedia
    add("media-loading", MediaView(service: MediaService(providers: [hanging])), 520, 190)
    add("media-noplayer", MediaView(service: a11yMediaService([A11yMediaProvider()])), 520, 190)
    let errSvc = MediaService(providers: []); errSvc.start()
    add("media-error", MediaView(service: errSvc), 520, 190)
    add("media-ready-playing", MediaView(service: a11yMediaService([A11yMediaProvider()], item: MediaItem(title: "So What", artist: "Miles Davis", duration: 200, position: 83, isPlaying: true))), 520, 190)
    add("media-ready-paused", MediaView(service: a11yMediaService([A11yMediaProvider()], item: MediaItem(title: "Sin posición", artist: nil, duration: 200, isPlaying: false))), 520, 190)
    add("media-needs-permission", MediaView(service: a11yMediaService([A11yMediaProvider("music", caps: [.openSource], auth: .notDetermined)], item: MediaItem(title: "Sin permiso", isPlaying: true))), 520, 190)
    add("media-denied", MediaView(service: a11yMediaService([A11yMediaProvider("spotify", caps: [.openSource], auth: .denied)], item: MediaItem(title: "Denegado", isPlaying: false))), 520, 190)

    // Calendario
    add("calendar-loading", CalendarView(service: a11yCalService(.authorized, ready: false)), 520, 230)
    add("calendar-not-determined", CalendarView(service: a11yCalService(.notDetermined)), 520, 230)
    add("calendar-denied", CalendarView(service: a11yCalService(.denied)), 520, 230)
    add("calendar-restricted", CalendarView(service: a11yCalService(.restricted)), 520, 230)
    add("calendar-empty", CalendarView(service: a11yCalService(.authorized)), 520, 230)
    add("calendar-ready", CalendarView(service: a11yCalService(.authorized, events: [
        CalendarEvent(id: "1", title: "Reunión de equipo", start: a11yAt(24, 16), end: a11yAt(24, 17), calendarTitle: "Trabajo"),
        CalendarEvent(id: "2", title: "Guardia nocturna", start: a11yAt(24, 23), end: a11yAt(25, 1), calendarTitle: "Guardias"),
    ])), 520, 260)
    add("calendar-error", CalendarView(service: a11yCalService(.authorized, failure: "El almacén de calendarios no respondió.")), 520, 230)

    // Widgets
    let wClock = A11yClock(a11yNow)
    let dateW = DateService(now: { a11yNow }, calendar: a11yCal(), locale: Locale(identifier: "es_ES"), center: NotificationCenter())
    let tIdle = TimerService(clock: { wClock.now }, duration: 300)
    add("widgets-timer-idle", WidgetsView(registry: WidgetRegistry(widgets: [tIdle])), 520, 260)
    let tRun = TimerService(clock: { wClock.now }, duration: 300); tRun.start()
    add("widgets-timer-running", WidgetsView(registry: WidgetRegistry(widgets: [tRun])), 520, 260)
    let tPause = TimerService(clock: { wClock.now }, duration: 300); tPause.start(); tPause.pause()
    add("widgets-timer-paused", WidgetsView(registry: WidgetRegistry(widgets: [tPause])), 520, 260)
    let tFin = TimerService(clock: { wClock.now }, duration: 60); tFin.start(); wClock.now = a11yNow.addingTimeInterval(120); tFin.refresh()
    add("widgets-timer-finished", WidgetsView(registry: WidgetRegistry(widgets: [tFin])), 520, 260)
    let bat = BatteryService(source: A11yPower(PowerReading(hasBattery: true, percent: 80, isCharging: true, isPluggedIn: true)), center: NotificationCenter())
    bat.refresh(); axPump(0.2) { bat.state == .ready }
    add("widgets-all", WidgetsView(registry: WidgetRegistry(widgets: [tIdle, bat, dateW, QuickActionsService()])), 520, 360)
    let failing = A11yPower(PowerReading(hasBattery: true, percent: 50))
    failing.fail = true
    let batErr = BatteryService(source: failing, center: NotificationCenter())
    batErr.refresh(); axPump(0.2) { if case .error = batErr.state { return true } else { return false } }
    add("widgets-battery-error", WidgetsView(registry: WidgetRegistry(widgets: [batErr])), 520, 220)
    add("widgets-empty", WidgetsView(registry: WidgetRegistry(widgets: [])), 520, 200)

    // Onboarding y ajustes
    for (name, step) in [("onboarding-welcome", OnboardingStep.welcome), ("onboarding-privacy", .privacy), ("onboarding-modules", .modules)] {
        add(name, OnboardingView(store: SettingsStore(defaults: a11yFreshDefaults()), initialStep: step, onFinish: {}), 520, 440)
    }
    for cat in SettingsCategory.allCases {
        // Alto suficiente para que el Form no muestre barra de desplazamiento (sus botones internos no tienen nombre).
        add("settings-\(cat.rawValue)", SettingsView(store: SettingsStore(defaults: a11yFreshDefaults()), initial: cat), 720, 760)
    }
    return out
}

// MARK: - Reglas

/// Roles de control interactivo (AppKit).
private let axInteractive: Set<String> = ["AXButton", "AXCheckBox", "AXSlider", "AXPopUpButton", "AXMenuButton", "AXIncrementor", "AXRadioButton", "AXTextField"]

/// Nombre técnico: identificador de SF Symbol o clave (p. ej. «xmark», «pause.fill», «square.grid.2x2»).
/// Los nombres de archivo («foto.png») coinciden con el patrón, así que se excluyen por extensión.
private let axFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "pdf", "txt", "md", "rtf", "csv", "json", "html", "mov", "mp4", "mp3", "m4a", "wav", "zip", "docx", "xlsx", "pptx", "key", "pages", "numbers", "swift"]
private func axIsTechnical(_ s: String) -> Bool {
    guard s.range(of: #"^[a-z][a-z0-9]*([.][a-z0-9]+)*$"#, options: .regularExpression) != nil else { return false }
    return !axFileExtensions.contains(String(s.split(separator: ".").last ?? ""))
}

@MainActor private func all(_ m: AXMount, _ pred: (AXNode) -> Bool) -> [AXNode] { m.root.all.filter(pred) }

@MainActor private func controls(_ m: AXMount) -> [AXNode] { all(m) { axInteractive.contains($0.role) } }

/// Reglas 1-3 sobre todos los controles de la pantalla. Un solo aserto por regla y pantalla (lista de
/// incumplimientos en el mensaje) para no inflar el recuento con repeticiones.
@MainActor private func auditControls(_ t: SelfCheck, _ screen: String, _ m: AXMount, at: String = "") {
    let unnamed = controls(m).filter { $0.name.isEmpty }.map { "\($0.role)" }
    let where_ = at.isEmpty ? "" : " — líneas de control: \(at)"
    t.expect(unnamed.isEmpty, "FINDING: [\(screen)] \(unnamed.count) control(es) sin nombre accesible (\(unnamed.joined(separator: ", "))): VoiceOver no sabe qué es\(where_)")
    let technical = controls(m).filter { !$0.name.isEmpty && axIsTechnical($0.name) }.map(\.name)
    t.expect(technical.isEmpty, "FINDING: [\(screen)] nombre técnico (SF Symbol/clave) en control: \(technical)")
    let noPress = controls(m).filter { ($0.role == "AXButton" || $0.role == "AXCheckBox") && !$0.pressable }.map(\.name)
    t.expect(noPress.isEmpty, "FINDING: [\(screen)] botón/casilla sin acción de pulsación: \(noPress)")
    // Regla 3: imágenes decorativas expuestas sin nombre (deben estar ocultas).
    let bareImages = all(m) { $0.role == "AXImage" && $0.name.isEmpty }.count
    t.expect(bareImages == 0, "FINDING: [\(screen)] \(bareImages) imagen(es) decorativa(s) expuesta(s) sin ocultar")
}

/// Regla 4 (indicio, no VoiceOver): cada control habilitado debe tener un KeyViewProxy en el anillo de teclado.
@MainActor private func auditKeyboard(_ t: SelfCheck, _ screen: String, _ m: AXMount, message: String? = nil) {
    let enabled = controls(m).filter(\.enabled).count
    t.expect(m.keyProxies >= enabled, message ?? "FINDING: [\(screen)] anillo de teclado incompleto: \(m.keyProxies) proxies para \(enabled) controles habilitados")
}

/// Estado vacío/error legible: hay texto humano (no identificadores) de al menos `minWords` palabras.
@MainActor private func auditHumanText(_ t: SelfCheck, _ screen: String, _ m: AXMount, minWords: Int = 3) {
    let texts = all(m) { ($0.role == "AXStaticText" || $0.role == "AXHeading") && !$0.text.isEmpty }.map(\.text)
    let longEnough = texts.filter { $0.split(separator: " ").count >= minWords }
    t.expect(!longEnough.isEmpty, "[\(screen)] sin mensaje legible (texto de ≥\(minWords) palabras): \(texts)")
}

@MainActor private func has(_ m: AXMount, _ s: String) -> Bool { m.root.all.contains { $0.name == s || $0.text == s } }
@MainActor private func hasContaining(_ m: AXMount, _ s: String) -> Bool {
    m.root.all.contains { $0.name.contains(s) || $0.text.contains(s) }
}

// MARK: - Entrada

@MainActor func runAccessibilitySuite(_ t: SelfCheck) {
    axBootstrap()
    let s = a11yScreens()
    func m(_ name: String) -> AXMount { s[name]! }

    // --- AuraDesignSystem: navegación de módulos, panel expandido y estados compactos ---
    let nav = m("nav-home")
    auditControls(t, "nav-home", nav)
    let navNames = controls(nav).map(\.name)
    t.expect(navNames == ["Inicio", "Multimedia", "Estantería", "Calendario", "Widgets", "Portapapeles"], "ModuleNavBar: nombres de módulo \(navNames)")
    let selected = controls(nav).filter(\.selected).map(\.name)
    t.expect(selected == ["Inicio"], "ModuleNavBar: exactamente el módulo activo seleccionado (esperado [Inicio], obtenido \(selected))")
    t.expect(has(nav, "Módulos"), "ModuleNavBar: grupo «Módulos»")
    auditKeyboard(t, "nav-home", nav)

    let chrome = m("chrome-home")
    auditControls(t, "chrome-home", chrome)
    t.expect(has(chrome, "Panel de Aura Notch"), "ExpandedChrome: panel nombrado")
    let gear = controls(chrome).first { $0.name == "Ajustes" }
    t.expect(gear != nil && gear?.help == "Abre los ajustes de Aura Notch", "ExpandedChrome: botón Ajustes con ayuda")
    t.expect(all(chrome) { $0.role == "AXHeading" && $0.label == "Inicio" }.count == 1, "ExpandedChrome: título de módulo como encabezado")
    auditKeyboard(t, "chrome-home", chrome)

    let cPlay = m("compact-media-playing")
    t.expect(has(cPlay, "Reproduciendo, 3:20"), "CompactContent: actividad de medios anunciada con su detalle")
    t.expect(has(m("compact-media-paused"), "En pausa, Título"), "CompactContent: estado en pausa anunciado")
    t.expect(all(m("compact-error")) { $0.name.hasPrefix("Error") }.count == 1, "CompactContent: error anunciado")
    t.expect(m("compact-idle").root.all.allSatisfy { $0.text.isEmpty && !axInteractive.contains($0.role) },
             "CompactContent: sin actividad no expone nada (oculto a VoiceOver)")

    // --- Inicio ---
    let quiet = m("home-quiet")
    auditControls(t, "home-quiet", quiet)
    t.expect(has(quiet, "Resumen de Inicio"), "Inicio: resumen nombrado")
    t.expect(all(quiet) { $0.role == "AXHeading" && $0.label?.contains("octubre") == true }.count == 1, "Inicio: fecha como encabezado")
    t.expect(controls(quiet).isEmpty, "Inicio (vacío): sin controles")
    t.expect(hasContaining(m("home-loading"), "Cargando"), "Inicio (cargando): muestra «Cargando…» en vez del saludo")
    let tRunning = m("home-timer-running")
    auditControls(t, "home-timer-running", tRunning)
    t.expect(hasContaining(tRunning, "En marcha, quedan"), "Inicio (temporizador en marcha): tarjeta con tiempo restante hablado")
    t.expect(has(tRunning, "Pausar") && has(tRunning, "Cancelar temporizador"), "Inicio (temporizador): controles Pausar/Cancelar nombrados")
    auditKeyboard(t, "home-timer-running", tRunning)
    t.expect(hasContaining(m("home-timer-paused"), "En pausa, quedan") && has(m("home-timer-paused"), "Reanudar"), "Inicio (pausado): estado y Reanudar")
    t.expect(hasContaining(m("home-timer-finished"), "Terminado") && has(m("home-timer-finished"), "Descartar"), "Inicio (terminado): estado y Descartar")
    let hm = m("home-media")
    auditControls(t, "home-media", hm)
    t.expect(hasContaining(hm, "Suena ahora: So What, Miles Davis"), "Inicio (medios): tarjeta con título y artista")
    t.expect(hasContaining(m("home-event"), "Hoy: Reunión de equipo"), "Inicio (evento): eventos de hoy nombrados")
    t.expect(has(m("home-shelf"), "2 elementos en la estantería"), "Inicio (estantería): recuento nombrado")
    t.expect(hasContaining(m("home-battery-low"), "Batería 12 %, Batería baja"), "Inicio (batería): nivel y estado nombrados en la cabecera")

    // --- Estantería ---
    let shelfEmpty = m("shelf-empty")
    auditControls(t, "shelf-empty", shelfEmpty)
    auditHumanText(t, "shelf-empty", shelfEmpty)
    t.expect(has(shelfEmpty, "Estantería vacía"), "Estantería (vacía): título del estado vacío")
    let addAlt = [shelfEmpty, m("shelf-busy")].contains { mount in
        mount.root.all.contains { n in
            n.actions.contains { $0.contains("Añad") || $0.contains("Pegar") } || n.name.contains("Añad") || n.name.contains("Pegar") || n.name.contains("Importar")
        }
    }
    t.expect(addAlt, "FINDING: [shelf] no hay alternativa de teclado/VoiceOver para añadir archivos: solo se puede arrastrar (ShelfView.swift:50 .dropDestination)")
    let shelfBusy = m("shelf-busy")
    auditControls(t, "shelf-busy", shelfBusy)
    let toolbar = controls(shelfBusy).filter { !["Informe.pdf", "foto.png", "example.com/articulo"].contains($0.name) }
    let disabledNoSelection = toolbar.filter { !$0.enabled }.map(\.name)
    t.expect(Set(disabledNoSelection) == ["Abrir", "Mostrar en Finder", "Copiar ruta", "Compartir…", "Enviar por AirDrop", "Quitar de la estantería"],
             "Estantería: acciones sobre selección deshabilitadas sin selección (\(disabledNoSelection))")
    t.expect(toolbar.contains { $0.name == "Limpiar estantería" && $0.enabled }, "Estantería: «Limpiar» siempre disponible")
    t.expect(has(shelfBusy, "Informe.pdf") && has(shelfBusy, "foto.png"), "Estantería: elementos nombrados por archivo")
    auditKeyboard(t, "shelf-busy", shelfBusy)
    let corrupt = m("shelf-corrupt")
    auditControls(t, "shelf-corrupt", corrupt)
    t.expect(hasContaining(corrupt, "No se pudo leer la estantería"), "Estantería (dañada): aviso legible")
    t.expect(has(corrupt, "Descartar"), "Estantería (dañada): botón Descartar nombrado")
    let missingShelf = m("shelf-missing")
    auditControls(t, "shelf-missing", missingShelf)
    t.expect(has(missingShelf, "desaparecido.txt, Archivo no encontrado"), "Estantería (ausente): tarjeta anuncia que el archivo falta")
    t.expect(has(missingShelf, "Recuperar") && has(missingShelf, "Quitar de la estantería"), "Estantería (ausente): Recuperar/Quitar nombrados")

    // --- Multimedia ---
    t.expect(hasContaining(m("media-loading"), "Buscando reproductores"), "Multimedia (cargando): estado anunciado")
    let mNo = m("media-noplayer")
    auditHumanText(t, "media-noplayer", mNo)
    t.expect(has(mNo, "Nada en reproducción"), "Multimedia (sin reproductor): título del estado vacío")
    let mErr = m("media-error")
    auditControls(t, "media-error", mErr)
    auditHumanText(t, "media-error", mErr)
    t.expect(has(mErr, "Multimedia no disponible") && has(mErr, "Reintentar"), "Multimedia (error): título y Reintentar")
    let mPlay = m("media-ready-playing")
    auditControls(t, "media-ready-playing", mPlay)
    t.expect(has(mPlay, "Anterior") && has(mPlay, "Pausar") && has(mPlay, "Siguiente") && has(mPlay, "Abrir reproductor"),
             "Multimedia (reproduciendo): controles de transporte nombrados")
    let progress = all(mPlay) { $0.name == "Progreso" }
    t.expect(progress.count == 1, "Multimedia (reproduciendo): progreso presente")
    t.expect(progress.allSatisfy { $0.value?.isEmpty == false },
             "FINDING: [media-ready-playing] el progreso no expone su valor («1:23 de 3:20»): VoiceOver solo oye «Progreso» (MediaView.swift:110, accessibilityValue sobre elemento .ignore)")
    let mPaused = m("media-ready-paused")
    auditControls(t, "media-ready-paused", mPaused)
    t.expect(has(mPaused, "Reproducir"), "Multimedia (en pausa): botón Reproducir nombrado")
    let mPerm = m("media-needs-permission")
    auditControls(t, "media-needs-permission", mPerm)
    t.expect(has(mPerm, "Permitir control"), "Multimedia (sin permiso): acción «Permitir control» nombrada")
    let mDen = m("media-denied")
    auditControls(t, "media-denied", mDen)
    t.expect(has(mDen, "Abrir Ajustes del Sistema"), "Multimedia (denegado): acción para abrir Ajustes nombrada")

    // --- Calendario ---
    t.expect(hasContaining(m("calendar-loading"), "Cargando eventos"), "Calendario (cargando): estado anunciado")
    let cND = m("calendar-not-determined")
    auditControls(t, "calendar-not-determined", cND)
    t.expect(has(cND, "Permitir acceso"), "Calendario (sin determinar): botón de permiso nombrado")
    let cDen = m("calendar-denied")
    auditControls(t, "calendar-denied", cDen)
    auditHumanText(t, "calendar-denied", cDen)
    t.expect(has(cDen, "Acceso al calendario denegado") && has(cDen, "Abrir Ajustes del Sistema"), "Calendario (denegado): causa y acción")
    t.expect(has(m("calendar-restricted"), "Abrir Ajustes del Sistema"), "Calendario (restringido): acción nombrada")
    let cEmpty = m("calendar-empty")
    auditHumanText(t, "calendar-empty", cEmpty)
    t.expect(has(cEmpty, "Sin eventos próximos"), "Calendario (vacío): título del estado vacío")
    let cReady = m("calendar-ready")
    auditControls(t, "calendar-ready", cReady)
    t.expect(has(cReady, "Reunión de equipo, hoy de 16:00 a 17:00, calendario Trabajo"), "Calendario (listo): evento anunciado completo")
    t.expect(controls(cReady).allSatisfy { $0.help == "Abre Calendario" }, "Calendario (listo): cada evento indica que abre Calendario")
    auditKeyboard(t, "calendar-ready", cReady)
    let cErr = m("calendar-error")
    auditControls(t, "calendar-error", cErr)
    auditHumanText(t, "calendar-error", cErr)
    t.expect(has(cErr, "No se pudieron cargar los eventos") && has(cErr, "Reintentar"), "Calendario (error): causa y reintento")

    // --- Widgets ---
    let wIdle = m("widgets-timer-idle")
    auditControls(t, "widgets-timer-idle", wIdle)
    t.expect(has(wIdle, "Temporizador") && has(wIdle, "Iniciar") && has(wIdle, "1 min"), "Widgets (temporizador parado): controles nombrados")
    t.expect(all(wIdle) { $0.name.hasPrefix("More") }.isEmpty,
             "FINDING: [widgets] el menú de la tarjeta se anuncia como «More» (inglés, SF Symbol «ellipsis») en vez de «Opciones de Temporizador» (WidgetsView.swift:76 accessibilityLabel no llega al nodo)")
    let wRun = m("widgets-timer-running")
    auditControls(t, "widgets-timer-running", wRun)
    let remaining = all(wRun) { $0.name == "Tiempo restante" }
    t.expect(remaining.count == 1 && remaining.allSatisfy { $0.value?.isEmpty == false },
             "FINDING: [widgets-timer-running] el tiempo restante no expone su valor (TimerService.swift:247, accessibilityValue sobre elemento .ignore)")
    t.expect(has(wRun, "Pausar") && has(wRun, "Cancelar"), "Widgets (temporizador en marcha): Pausar/Cancelar nombrados")
    let wPaused = m("widgets-timer-paused")
    t.expect(has(wPaused, "Reanudar") && has(wPaused, "En pausa"), "Widgets (temporizador en pausa): Reanudar y estado")
    let wFin = m("widgets-timer-finished")
    t.expect(has(wFin, "Terminado") && has(wFin, "Reiniciar") && has(wFin, "Cerrar"), "Widgets (temporizador terminado): estado y acciones")
    let wAll = m("widgets-all")
    auditControls(t, "widgets-all", wAll)
    for card in ["Temporizador", "Batería", "Fecha", "Acciones"] {
        t.expect(all(wAll) { $0.name == card }.count >= 1, "Widgets: tarjeta «\(card)» nombrada")
    }
    t.expect(has(wAll, "Abrir Descargas") && has(wAll, "Copiar fecha"), "Widgets: acciones rápidas nombradas")
    let wErr = m("widgets-battery-error")
    auditControls(t, "widgets-battery-error", wErr)
    auditHumanText(t, "widgets-battery-error", wErr)
    t.expect(has(wErr, "Reintentar") && hasContaining(wErr, "No se pudo leer el estado de energía"), "Widgets (batería con error): causa y reintento")
    let wEmpty = m("widgets-empty")
    auditHumanText(t, "widgets-empty", wEmpty)
    t.expect(has(wEmpty, "Sin widgets"), "Widgets (vacío): título del estado vacío")

    // --- Onboarding ---
    for (name, title, next) in [("onboarding-welcome", "Tu notch, más útil", "Continuar"),
                                ("onboarding-privacy", "Tus datos se quedan contigo", "Continuar"),
                                ("onboarding-modules", "Elige tus módulos", "Empezar")] {
        let mo = m(name)
        auditControls(t, name, mo)
        t.expect(has(mo, title), "\(name): encabezado del paso")
        t.expect(has(mo, next), "\(name): botón «\(next)» nombrado")
        t.expect(hasContaining(mo, "Paso "), "\(name): indicador de paso")
    }
    let obModules = m("onboarding-modules")
    let toggles = controls(obModules).filter { $0.role == "AXCheckBox" }
    t.expect(toggles.map(\.name) == ["Medios", "Estantería", "Calendario", "Widgets"] && toggles.allSatisfy { $0.value == "1" },
             "Onboarding: interruptores de módulos nombrados y con estado (\(toggles.map(\.name)))")
    auditKeyboard(t, "onboarding-modules", obModules,
                  message: "FINDING: [onboarding-modules] \(obModules.keyProxies) proxies de teclado para \(controls(obModules).filter(\.enabled).count) controles: los interruptores (.toggleStyle(.switch), OnboardingView.swift:112) no entran en el anillo de foco. Indicio AppKit, verificar con Tab real")
    auditKeyboard(t, "onboarding-welcome", m("onboarding-welcome"))
    auditKeyboard(t, "onboarding-privacy", m("onboarding-privacy"))

    // --- Ajustes: barra lateral, categorías y controles ---
    // Líneas de producción de los controles de cada categoría (SettingsView.swift), para el informe.
    let settingsLines: [SettingsCategory: String] = [
        .general: "SettingsView.swift:64, 76", .interaction: "SettingsView.swift:88-90, 94, 101",
        .animation: "SettingsView.swift:113, 118", .modules: "SettingsView.swift:132, 136",
        .privacy: "SettingsView.swift:145-146",
    ]
    for cat in SettingsCategory.allCases {
        let name = "settings-\(cat.rawValue)"
        let mo = m(name)
        let selectedRows = all(mo) { $0.role == "AXRow" && $0.selected }
        let selText = selectedRows.first.flatMap { r in r.all.first { $0.role == "AXStaticText" }?.value } ?? ""
        t.expect(selectedRows.count == 1 && selText == cat.rawValue, "\(name): categoría activa marcada en la barra lateral (\(selText))")
        auditControls(t, name, mo, at: settingsLines[cat] ?? "")
    }
    let inter = m("settings-Interacción")
    let hoverSlider = all(inter) { $0.role == "AXSlider" }.first
    t.expect(hoverSlider?.value.flatMap(Double.init) == 0.12, "Ajustes Interacción: el valor del retardo refleja el ajuste (\(hoverSlider?.value ?? "nil"))")
    t.expect(hasContaining(inter, "segundos"),
             "FINDING: [settings-Interacción] el retardo se anuncia sin unidades: el accessibilityValue «%.2f segundos» no llega al slider (SettingsView.swift:98)")
    t.expect(all(inter) { $0.role == "AXCheckBox" }.allSatisfy { $0.value != nil }, "Ajustes Interacción: los interruptores exponen su estado")
    let modules = m("settings-Módulos")
    let modNames = all(modules) { $0.role == "AXCheckBox" }.map(\.name)
    t.expect(modNames.count == NotchModule.allCases.count, "Ajustes Módulos: un interruptor por módulo (\(modNames))")
    // Solo las filas de módulo (con su casilla); las de la barra lateral de categorías también son AXRow.
    let moduleRows = all(modules) { $0.role == "AXRow" && $0.cls == "NSOutlineRow" && $0.all.contains { $0.role == "AXCheckBox" } }
    t.expect(moduleRows.count == NotchModule.allCases.count, "Ajustes Módulos: una fila por módulo de módulo (\(moduleRows.count))")
    // SwiftUI coloca las acciones personalizadas del List en el nodo hijo de la fila (verificado en el volcado del árbol).
    t.expect(moduleRows.allSatisfy { r in (r.actions + r.all.flatMap(\.actions)).contains { $0.lowercased().contains("move") || $0.contains("Mover") } },
             "FINDING: [settings-Módulos] el orden de los módulos solo se cambia arrastrando (SettingsView.swift:136 .onMove): sin acción de VoiceOver para mover")
    let privacy = m("settings-Privacidad")
    t.expect(has(privacy, "Borrar todos los datos…"), "Ajustes Privacidad: acción destructiva nombrada")
    let advanced = m("settings-Avanzado")
    let undo = controls(advanced).first { $0.name == "Deshacer último cambio" }
    t.expect(undo != nil && !(undo?.enabled ?? true), "Ajustes Avanzado: «Deshacer» deshabilitado sin cambios")
    let about = m("settings-Acerca de")
    t.expect(hasContaining(about, "Aura Notch") && hasContaining(about, "Sin telemetría"), "Ajustes Acerca de: versión y nota nombradas")

    // Ajustes (Form): el anillo de teclado no es observable de forma fiable desde AppKit en el harness
    // (3 controles → 1 proxy en el experimento). No se afirma nada sobre Tab en la ventana de ajustes.
    // Etiquetas de interruptores, selectores y deslizadores de Form: ver los FINDING de auditControls.
}
