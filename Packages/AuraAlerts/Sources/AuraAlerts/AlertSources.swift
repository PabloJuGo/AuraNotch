import Foundation

/// Textos de los avisos propios (§5.5). Cortos: caben en el ala del notch cerrado.
enum AlertStrings {
    private static func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

    static let plugged = tr("Conectado"), unplugged = tr("En batería"), charged = tr("Cargada")
    static let pluggedSpoken = tr("Cargador conectado"), unpluggedSpoken = tr("Cargador desconectado")
    static let chargedSpoken = tr("Batería cargada al 100 %")
    static let timerDone = tr("Tiempo cumplido"), timerDoneSpoken = tr("Temporizador terminado")

    static func meeting(_ title: String, _ m: Int) -> String {
        let short = String(title.prefix(10)) + (title.count > 10 ? "…" : "") // el ala da para ~20 caracteres
        return String(localized: "\(short) · \(m) min")
    }
    static func meetingSpoken(_ title: String, _ m: Int) -> String {
        m == 1 ? String(localized: "\(title) empieza en un minuto") : String(localized: "\(title) empieza en \(m) minutos")
    }
}

public extension AuraAlert {
    static var timerFinished: AuraAlert { AuraAlert(symbol: "timer", text: AlertStrings.timerDone, spoken: AlertStrings.timerDoneSpoken) }
}

/// Lo mínimo que hace falta saber de un evento (AuraAlerts no depende de AuraCalendar).
public struct UpcomingMeeting: Equatable, Sendable {
    public var id: String, title: String, start: Date, isAllDay: Bool
    public init(id: String, title: String, start: Date, isAllDay: Bool = false) {
        self.id = id; self.title = title; self.start = start; self.isAllDay = isAllDay
    }
}

/// Aviso de reunión ~`lead` antes. Una sola espera hasta el instante del aviso, recalculada en cada `update`
/// (cambian los eventos): nada de polling. `sleep` y `now` son inyectables para las pruebas.
@MainActor public final class MeetingAlerts {
    private let center: AlertCenter
    private let lead: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var meetings: [UpcomingMeeting] = []
    private var announced: Set<String> = []
    private var task: Task<Void, Never>?

    public init(center: AlertCenter, lead: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.center = center; self.lead = lead; self.now = now; self.sleep = sleep
    }

    public func update(_ list: [UpcomingMeeting]) {
        meetings = list
        reschedule()
    }

    public func stop() { task?.cancel(); task = nil; meetings = [] }

    private func reschedule() {
        task?.cancel(); task = nil
        let t = now()
        guard let next = meetings.filter({ !$0.isAllDay && $0.start > t && !announced.contains(key($0)) }).min(by: { $0.start < $1.start }) else { return }
        let wait = next.start.addingTimeInterval(-lead).timeIntervalSince(t)
        task = Task { [weak self, sleep] in
            if wait > 0 { try? await sleep(wait) }
            guard !Task.isCancelled else { return }
            self?.fire(next.start)
        }
    }

    private func fire(_ start: Date) {
        let t = now()
        // Reuniones simultáneas: un solo aviso (el siguiente reemplazaría al primero al instante).
        let group = meetings.filter { !$0.isAllDay && $0.start == start }
        group.forEach { announced.insert(key($0)) }
        if start > t, let first = group.first {
            let m = max(1, Int((start.timeIntervalSince(t) / 60).rounded(.up)))
            let extra = group.count > 1 ? " +\(group.count - 1)" : ""
            center.post(AuraAlert(symbol: "calendar", text: AlertStrings.meeting(first.title, m) + extra,
                                  spoken: AlertStrings.meetingSpoken(first.title, m)), for: .seconds(8))
        }
        reschedule()
    }

    private func key(_ m: UpcomingMeeting) -> String { "\(m.id)|\(m.start.timeIntervalSinceReferenceDate)" }
}

/// Estado de energía relevante para avisar (AuraAlerts no depende de AuraWidgets).
public struct PowerSnapshot: Equatable, Sendable {
    public var pluggedIn: Bool, charged: Bool
    public init(pluggedIn: Bool, charged: Bool) { self.pluggedIn = pluggedIn; self.charged = charged }
}

/// Avisa al conectar/desconectar el cargador y al completar la carga. La primera lectura solo fija la base.
@MainActor public final class PowerAlerts {
    private let center: AlertCenter
    private var last: PowerSnapshot?

    public init(center: AlertCenter) { self.center = center }

    /// `nil` = sin batería o lectura fallida.
    public func update(_ s: PowerSnapshot?) {
        defer { last = s }
        guard let s, let p = last else { return }
        if s.pluggedIn != p.pluggedIn {
            center.post(s.pluggedIn
                ? AuraAlert(symbol: "bolt.fill", text: AlertStrings.plugged, spoken: AlertStrings.pluggedSpoken)
                : AuraAlert(symbol: "bolt.slash.fill", text: AlertStrings.unplugged, spoken: AlertStrings.unpluggedSpoken))
        } else if s.charged && !p.charged {
            center.post(AuraAlert(symbol: "battery.100percent.bolt", text: AlertStrings.charged, spoken: AlertStrings.chargedSpoken))
        }
    }
}
