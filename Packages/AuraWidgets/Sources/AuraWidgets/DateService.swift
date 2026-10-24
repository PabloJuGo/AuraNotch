import AuraDesignSystem
import Foundation
import Observation
import SwiftUI

/// Widget de fecha. Sin timer: se actualiza con `NSCalendarDayChanged` (y cambios de reloj/zona) solo mientras está activo.
@MainActor @Observable
public final class DateService: AuraWidget {
    public private(set) var date: Date
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    public let calendar: Calendar
    public let locale: Locale

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent,
                locale: Locale = .autoupdatingCurrent, center: NotificationCenter = .default) {
        self.now = now; self.calendar = calendar; self.locale = locale; self.center = center; date = now()
    }

    public let manifest = WidgetManifest(id: "date", name: WidgetStrings.dateName, symbol: "calendar")
    public var state: WidgetState { .ready }
    public var weekday: String { date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)).firstCapitalized }
    public var day: String { String(calendar.component(.day, from: date)) }
    public var monthYear: String { date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()).firstCapitalized }
    public var summary: String { date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)) }

    public func setActive(_ active: Bool) {
        if active, tokens.isEmpty {
            date = now()  // pudo cambiar el día mientras estaba inactivo
            let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
            tokens = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        } else if !active {
            tokens.forEach(center.removeObserver); tokens = []
        }
    }
    public func refresh() { date = now() }
    public func makeBody() -> AnyView { AnyView(DateBody(service: self)) }
}

struct DateBody: View {
    let service: DateService
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(service.day).font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(AuraColor.primaryText.color)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(service.weekday).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color)
                Text(service.monthYear).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.summary)
    }
}

private extension String { var firstCapitalized: String { prefix(1).uppercased() + dropFirst() } }
