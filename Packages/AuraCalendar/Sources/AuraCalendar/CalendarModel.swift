import AuraDesignSystem
import Foundation

/// Evento ya reducido a lo que se muestra. Solo vive en memoria (la ventana próxima); nunca se persiste.
public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarTitle: String
    public var calendarColor: RGB?
    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendarTitle: String = "", calendarColor: RGB? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.calendarTitle = calendarTitle; self.calendarColor = calendarColor
    }
}

public enum CalendarState: Equatable, Sendable {
    case loading
    /// No se puede leer ni preguntar: acceso restringido por el sistema o concedido solo de escritura.
    case noPermission
    /// Aún no se ha preguntado: la vista ofrece el botón explícito.
    case notDetermined
    case denied
    case empty, ready
    case error(String)
}

public enum CalendarAuthStatus: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted, writeOnly
}

/// Autorización de Calendarios. `status()` NO debe mostrar diálogo; `requestAccess()` sí puede.
public protocol CalendarAuthorizing: Sendable {
    func status() -> CalendarAuthStatus
    func requestAccess() async throws -> Bool
}

/// Origen de eventos (EventKit en producción; dobles en pruebas). Solo lectura.
public protocol EventSource: Sendable {
    /// Eventos que se solapan con [from, to). Se ejecuta fuera del MainActor.
    func events(from: Date, to: Date) async throws -> [CalendarEvent]
    /// Emite cuando el almacén cambia (EKEventStoreChanged). Sin polling.
    func changes() -> AsyncStream<Void>
}

/// Acciones hacia fuera de la app (no se ejecutan en pruebas salvo con dobles).
public protocol CalendarOpening: Sendable {
    func openPrivacySettings()
    /// Abre la app Calendario. No hay URL pública documentada para un evento concreto.
    func openCalendarApp()
}

public struct CalendarCompactInfo: Equatable, Sendable {
    public var detail: String
    public var accessibilityLabel: String
}
