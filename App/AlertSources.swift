import AuraAlerts
import AuraCalendar
import AuraWidgets
import Observation

/// Pegamento fino: conecta los servicios con los publicadores de avisos de AuraAlerts. Solo eventos, sin polling.
/// Batería con su propia suscripción IOPS: `BatteryService` solo escucha mientras su widget está visible.
@MainActor final class AlertSources {
    private let calendar: CalendarService
    private let meetings: MeetingAlerts
    private let power: PowerAlerts
    private let timer: TimerService
    private let alerts: AlertCenter
    private let source = IOKitPowerSource()
    private var cancelPower: (@MainActor () -> Void)?

    init(alerts: AlertCenter, calendar: CalendarService, timer: TimerService) {
        self.alerts = alerts; self.calendar = calendar; self.timer = timer
        meetings = MeetingAlerts(center: alerts); power = PowerAlerts(center: alerts)
    }

    func start() {
        timer.onFinished = { [alerts] _ in MainActor.assumeIsolated { alerts.post(.timerFinished) } }
        readPower()
        cancelPower = source.observe { [weak self] in self?.readPower() }
        observeCalendar()
    }

    func stop() { cancelPower?(); cancelPower = nil; meetings.stop(); timer.onFinished = nil }

    private func readPower() {
        guard let r = try? source.read(), r.hasBattery else { return power.update(nil) }
        power.update(PowerSnapshot(pluggedIn: r.isPluggedIn, charged: r.isCharged))
    }

    /// `events` queda vacío si el módulo está apagado o sin permiso: entonces no hay nada que avisar.
    private func observeCalendar() {
        meetings.update(calendar.events.map { UpcomingMeeting(id: $0.id, title: calendar.displayTitle($0), start: $0.start, isAllDay: $0.isAllDay) })
        withObservationTracking {
            _ = calendar.events
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeCalendar() }
        }
    }
}
