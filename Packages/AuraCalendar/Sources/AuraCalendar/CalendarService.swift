import AuraCore
import Foundation
import Observation

/// Resultado de la solicitud de permiso, ya sin errores lanzados (cruza hilos).
enum AccessOutcome: Sendable { case granted, denied, failed(String) }

/// Reanuda una continuación una sola vez (carrera solicitud/timeout).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<AccessOutcome?, Never>?
    init(_ c: CheckedContinuation<AccessOutcome?, Never>) { cont = c }
    func resume(_ v: AccessOutcome?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: v)
    }
}

/// Calendario (UI-08, AURA-015). Solo lectura, solo memoria, sin cargar nada hasta `start()`.
@MainActor @Observable
public final class CalendarService {
    public private(set) var state: CalendarState = .loading
    public private(set) var events: [CalendarEvent] = []
    public private(set) var isRequesting = false
    /// Aviso no bloqueante (p. ej. timeout de la solicitud).
    public private(set) var notice: String?
    public let windowDays: Int, limit: Int
    @ObservationIgnored public private(set) var renderRevision = 0

    @ObservationIgnored private let authorizer: any CalendarAuthorizing
    @ObservationIgnored private let source: any EventSource
    @ObservationIgnored private let opener: any CalendarOpening
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let requestTimeout: Duration
    @ObservationIgnored private var started = false
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<AccessOutcome, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init(authorizer: any CalendarAuthorizing, source: any EventSource, opener: any CalendarOpening,
                calendar: Calendar = .current, now: @escaping () -> Date = Date.init,
                center: NotificationCenter = .default, windowDays: Int = 7, limit: Int = 10,
                debounce: Duration = .milliseconds(300), requestTimeout: Duration = .seconds(20)) {
        self.authorizer = authorizer; self.source = source; self.opener = opener
        self.calendar = calendar; self.now = now; self.center = center
        self.windowDays = max(1, windowDays); self.limit = max(1, limit)
        self.debounce = debounce; self.requestTimeout = requestTimeout
    }

    /// Producción: EventKit real + apertura por NSWorkspace. No toca EventKit hasta `start()`.
    public convenience init(windowDays: Int = 7, limit: Int = 10) {
        let ek = EventKitCalendar()
        self.init(authorizer: ek, source: ek, opener: SystemCalendarOpener(), windowDays: windowDays, limit: limit)
    }

    // MARK: Ciclo de vida

    /// Módulo activado. Lee el estado de autorización (sin diálogo); solo carga si ya está concedido.
    public func start() {
        if !started {
            started = true
            for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleReload() }
                })
            }
        }
        evaluate()
    }

    /// Módulo desactivado: cancela todo y olvida los eventos.
    public func stop() {
        started = false
        epoch += 1
        loadTask?.cancel(); debounceTask?.cancel(); changesTask?.cancel()
        loadTask = nil; debounceTask = nil; changesTask = nil
        observers.forEach { center.removeObserver($0) }; observers = []
        set(&events, []); set(&state, .loading); set(&notice, nil)
    }

    /// Relee la autorización (sin diálogo); la vista la llama al aparecer por si cambió en Ajustes.
    public func refreshAuthorization() {
        guard started, state != .ready, state != .empty, state != .loading else { return }
        evaluate()
    }

    private func evaluate() {
        switch authorizer.status() {
        case .authorized:
            if changesTask == nil {
                let changes = source.changes()
                changesTask = Task { [weak self] in
                    for await _ in changes { if Task.isCancelled { break }; self?.scheduleReload() }
                }
            }
            reload()
        case .notDetermined: leaveUnauthorized(.notDetermined)
        case .denied: leaveUnauthorized(.denied)
        case .restricted, .writeOnly: leaveUnauthorized(.noPermission)
        }
    }

    private func leaveUnauthorized(_ s: CalendarState) {
        changesTask?.cancel(); changesTask = nil
        epoch += 1; loadTask?.cancel()
        set(&events, []); set(&state, s)
    }

    // MARK: Carga

    /// Coalesce ráfagas (EKEventStoreChanged llega a menudo varias veces seguidas): una recarga por ventana.
    func scheduleReload() {
        guard started, debounceTask == nil else { return }
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.debounceTask = nil
            self.reload()
        }
    }

    /// Reintento manual.
    public func reload() {
        guard started, authorizer.status() == .authorized else { return }
        epoch += 1; let mine = epoch
        loadTask?.cancel()
        if events.isEmpty { set(&state, .loading) }
        let start = now()
        let startOfToday = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: windowDays, to: startOfToday) ?? start.addingTimeInterval(Double(windowDays) * 86_400)
        loadTask = Task { [source, weak self] in
            do {
                let found = try await source.events(from: start, to: end)
                guard !Task.isCancelled else { return }
                self?.apply(found, epoch: mine)
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error.localizedDescription, epoch: mine)
            }
        }
    }

    func apply(_ found: [CalendarEvent], epoch e: Int) {
        guard e == epoch else { return }  // resultado obsoleto
        let t = now()
        let shown = found.filter { $0.end > t || ($0.end == $0.start && $0.start >= t) }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
        set(&events, Array(shown)); set(&notice, nil)
        set(&state, shown.isEmpty ? .empty : .ready)
    }

    private func fail(_ message: String, epoch e: Int) {
        guard e == epoch else { return }
        set(&state, .error(message.isEmpty ? CalendarStrings.errorTitle : message))
    }

    // MARK: Permiso (solo desde el botón explícito)

    /// Solicita acceso. La llamada del sistema corre fuera del MainActor; si no responde en `requestTimeout`
    /// la UI se libera (la llamada sigue viva y, si termina, se aplica). Nunca hay dos solicitudes a la vez.
    public func requestAccess() async {
        guard started, authorizer.status() == .notDetermined || requestTask != nil else { return }
        let work: Task<AccessOutcome, Never>
        if let existing = requestTask { work = existing } else {
            let auth = authorizer
            work = Task.detached {
                do { return try await auth.requestAccess() ? .granted : .denied } catch { return .failed(error.localizedDescription) }
            }
            requestTask = work
            Task { [weak self] in
                let outcome = await work.value
                self?.requestFinished(outcome)
            }
        }
        set(&isRequesting, true); set(&notice, nil)
        let timeout = requestTimeout
        let raced: AccessOutcome? = await withCheckedContinuation { cont in
            let once = Once(cont)
            Task { once.resume(await work.value) }
            Task { try? await Task.sleep(for: timeout); once.resume(nil) }
        }
        if raced == nil, requestTask != nil { set(&isRequesting, false); set(&notice, CalendarStrings.timeoutNotice) }
    }

    private func requestFinished(_ outcome: AccessOutcome) {
        requestTask = nil
        set(&isRequesting, false)
        if case .failed(let m) = outcome { set(&notice, m.isEmpty ? CalendarStrings.denialFallback : m) } else { set(&notice, nil) }
        if started { evaluate() }
    }

    // MARK: Acciones (explícitas del usuario)

    public func openPrivacySettings() { opener.openPrivacySettings() }
    /// Abre la app Calendario (no hay forma pública fiable de abrir un evento concreto).
    public func open(_ event: CalendarEvent) { opener.openCalendarApp() }

    // MARK: Presentación

    var format: CalendarFormat { CalendarFormat(calendar: calendar, now: now()) }

    public func when(_ e: CalendarEvent) -> String { format.when(e) }
    public func displayTitle(_ e: CalendarEvent) -> String { format.title(e) }
    public func calendarName(_ e: CalendarEvent) -> String { format.calendarName(e) }
    /// «Reunión de equipo, hoy de 10:00 a 11:00, calendario Trabajo».
    public func accessibilityLabel(_ e: CalendarEvent) -> String { format.spoken(e) }

    /// Siguiente evento con hora que empieza en menos de 15 min; nil = nada que mostrar (Quiet by default).
    /// Es función de la hora: el anfitrión debe reevaluarla cuando le interese (no hay temporizador propio).
    public func compactInfo(at date: Date? = nil) -> CalendarCompactInfo? {
        let t = date ?? now()
        guard let e = events.first(where: { !$0.isAllDay && $0.start > t && $0.start.timeIntervalSince(t) < 900 }) else { return nil }
        let minutes = max(1, Int((e.start.timeIntervalSince(t) / 60).rounded(.up)))
        let title = format.title(e)
        let short = String(title.prefix(16)) + (title.count > 16 ? "…" : "")
        return CalendarCompactInfo(detail: CalendarStrings.inMinutes(short, minutes),
                                   accessibilityLabel: CalendarStrings.startsInMinutes(title, minutes))
    }

    private func set<T: Equatable>(_ keyPath: inout T, _ value: T) {
        guard keyPath != value else { return }
        keyPath = value; renderRevision += 1
    }
}
