import AppKit
import AuraDesignSystem
import EventKit
import Foundation

/// Implementación real sobre EventKit. SOLO LECTURA: nunca se llama a save/remove.
/// El `EKEventStore` se crea de forma perezosa al primer uso real; `status()` no lo crea ni muestra diálogo.
/// Sin verificar contra un calendario real.
public actor EventKitCalendar: EventSource, CalendarAuthorizing {
    private var store: EKEventStore?
    public init() {}

    private func theStore() -> EKEventStore {
        if let store { return store }
        let s = EKEventStore(); store = s; return s
    }

    public nonisolated func status() -> CalendarAuthStatus {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    static func map(_ s: EKAuthorizationStatus) -> CalendarAuthStatus {
        switch s {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .authorized
        case .writeOnly: .writeOnly
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    /// Puede mostrar el diálogo del sistema (y, sin Info.plist, abortar el proceso): solo desde el botón de la vista.
    public func requestAccess() async throws -> Bool {
        let store = theStore()
        return try await store.requestFullAccessToEvents()
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        let s = theStore()
        return s.events(matching: s.predicateForEvents(withStart: from, end: to, calendars: nil)).map { e in
            // Las repeticiones comparten eventIdentifier: se añade el inicio para distinguirlas.
            let base = e.eventIdentifier ?? UUID().uuidString
            return CalendarEvent(
                id: "\(base)|\(e.startDate.timeIntervalSince1970)", title: e.title ?? "",
                start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                calendarTitle: e.calendar?.title ?? "", calendarColor: Self.rgb(e.calendar?.cgColor))
        }
    }

    private static func rgb(_ c: CGColor?) -> RGB? {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return nil }
        return RGB(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { cont in
            let token = ObserverToken(NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: nil, queue: nil) { _ in cont.yield() })
            cont.onTermination = { _ in NotificationCenter.default.removeObserver(token.value) }
        }
    }
}

private final class ObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol
    init(_ v: NSObjectProtocol) { value = v }
}

/// Apertura real. Limitación documentada: no hay esquema público fiable para abrir un evento concreto
/// (`x-apple-calevent://` no está documentado), así que se abre la app Calendario.
public struct SystemCalendarOpener: CalendarOpening {
    public static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    public static let calendarBundleID = "com.apple.iCal"
    public init() {}

    public func openPrivacySettings() { NSWorkspace.shared.open(Self.privacyURL) }

    public func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.calendarBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
