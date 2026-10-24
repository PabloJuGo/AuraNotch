import AuraCalendar
import Foundation

/// EventKit puede abortar el proceso al pedir acceso sin `Info.plist` (binario suelto de `swift run`).
/// Solo se permite solicitar desde el `.app` empaquetado; leer el estado nunca muestra diálogo.
struct GuardedCalendarAuthorizer: CalendarAuthorizing {
    let base: any CalendarAuthorizing
    static var isPackaged: Bool { Bundle.main.bundleIdentifier != nil }

    func status() -> CalendarAuthStatus { base.status() }

    func requestAccess() async throws -> Bool {
        guard Self.isPackaged else {
            throw NSError(domain: "AuraNotch", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Para dar acceso al calendario abre la app empaquetada (Scripts/package-app.sh).")])
        }
        return try await base.requestAccess()
    }
}
