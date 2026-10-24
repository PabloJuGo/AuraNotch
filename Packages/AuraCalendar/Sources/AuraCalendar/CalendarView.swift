import AuraCore
import AuraDesignSystem
import SwiftUI

/// UI-08. Estados: loading, sin permiso, sin determinar, denegado, vacío, listo, error. Sin animación permanente.
public struct CalendarView: View {
    let service: CalendarService
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(service: CalendarService) { self.service = service }

    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    public var body: some View {
        content
            .padding(Space.sm)
            .animation(Motion.animation(.switchModule, motion), value: service.state)
            .onAppear { service.refreshAuthorization() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(CalendarStrings.group)
    }

    @ViewBuilder private var content: some View {
        switch service.state {
        case .loading:
            VStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text(CalendarStrings.loading).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .notDetermined:
            permission(symbol: "calendar", title: CalendarStrings.askTitle, message: CalendarStrings.askMessage) {
                if service.isRequesting {
                    HStack(spacing: Space.xs) {
                        ProgressView().controlSize(.small)
                        Text(CalendarStrings.waiting).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Button(CalendarStrings.allow) { Task { await service.requestAccess() } }
                        .buttonStyle(AuraButtonStyle(emphasis: .filled))
                }
            }
        case .denied:
            permission(symbol: "calendar.badge.exclamationmark", title: CalendarStrings.deniedTitle, message: CalendarStrings.deniedMessage) {
                Button(Strings.openSettings) { service.openPrivacySettings() }.buttonStyle(AuraButtonStyle(emphasis: .filled))
            }
        case .noPermission:
            permission(symbol: "calendar.badge.exclamationmark", title: CalendarStrings.restrictedTitle, message: CalendarStrings.restrictedMessage) {
                Button(Strings.openSettings) { service.openPrivacySettings() }.buttonStyle(AuraButtonStyle(emphasis: .filled))
            }
        case .empty:
            EmptyStateView(symbol: "calendar", title: CalendarStrings.emptyTitle,
                           message: CalendarStrings.emptyMessage(days: service.windowDays))
        case .error(let message):
            ErrorStateView(title: CalendarStrings.errorTitle, cause: message, solution: CalendarStrings.errorSolution,
                           onRetry: { service.start(); service.reload() },
                           onOpenSettings: { service.openPrivacySettings() })
        case .ready:
            list
        }
    }

    private func permission<A: View>(symbol: String, title: String, message: String, @ViewBuilder action: () -> A) -> some View {
        VStack(spacing: Space.sm) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AuraColor.secondaryText.color).accessibilityHidden(true)
            Text(title).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            action()
            if let notice = service.notice {
                Text(notice).font(AuraFont.secondary).foregroundStyle(AuraColor.warning.color)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(service.events) { row($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ e: CalendarEvent) -> some View {
        Button { service.open(e) } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                Circle().fill(e.calendarColor.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b) } ?? AuraColor.accent.color)
                    .frame(width: 8, height: 8).padding(.top, 5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayTitle(e)).font(AuraFont.body).foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                    Text(service.when(e)).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                    Text(service.calendarName(e)).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs).padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraColor.elevatedSurface.color, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.accessibilityLabel(e))
        .accessibilityHint(CalendarStrings.openHint)
        .accessibilityAddTraits(.isButton)
    }
}
