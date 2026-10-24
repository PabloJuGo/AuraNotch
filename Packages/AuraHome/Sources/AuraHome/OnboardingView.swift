import AuraCore
import AuraDesignSystem
import AuraPreferences
import SwiftUI

/// UI-01 · Onboarding en 3 pasos: qué hace, privacidad y permisos opt-in, y módulos.
/// Nunca solicita permisos: solo los explica. Los interruptores escriben en `SettingsStore.settings.disabledModules`.
/// Teclado: Intro = Continuar, Esc = Omitir, Tab recorre interruptores y botones.
public struct OnboardingView: View {
    let store: SettingsStore
    let isReturning: Bool
    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    /// `onFinish` se llama al terminar, omitir o cerrar; quien lo recibe marca `OnboardingState` y cierra.
    public init(store: SettingsStore, isReturning: Bool = false, initialStep: OnboardingStep = .welcome,
                onFinish: @escaping () -> Void) {
        self.store = store; self.isReturning = isReturning; self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(OnboardingStrings.stepOf(step.rawValue + 1, OnboardingStep.allCases.count))
                .font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            page
                .id(step)
                .transition(Motion.contentTransition(motion))
            Spacer(minLength: 0)
            footer
        }
        .padding(Space.xl)
        .frame(width: 520, height: 440)
        .background(AuraColor.surface.color)
        .environment(\.colorScheme, .dark)
        .animation(Motion.animation(.switchModule, motion), value: step)
        .accessibilityElement(children: .contain)
    }

    // MARK: Páginas

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            section(symbol: "rectangle.topthird.inset.filled",
                    title: isReturning ? OnboardingStrings.welcomeTitleReturning : OnboardingStrings.welcomeTitle) {
                Text(OnboardingStrings.welcomeBody)
                Text(OnboardingStrings.welcomeQuiet).foregroundStyle(AuraColor.secondaryText.color)
            }
        case .privacy:
            section(symbol: "lock.shield", title: OnboardingStrings.privacyTitle) {
                Text(OnboardingStrings.privacyLocal)
                Text(OnboardingStrings.privacyPermissions).foregroundStyle(AuraColor.secondaryText.color)
                VStack(alignment: .leading, spacing: Space.md) {
                    note("calendar", OnboardingStrings.privacyCalendarTitle, OnboardingStrings.privacyCalendarBody)
                    note("music.note", OnboardingStrings.privacyMediaTitle, OnboardingStrings.privacyMediaBody)
                }
                .padding(.top, Space.xs)
            }
        case .modules:
            section(symbol: "square.grid.2x2", title: OnboardingStrings.modulesTitle) {
                Text(OnboardingStrings.modulesBody).foregroundStyle(AuraColor.secondaryText.color)
                VStack(spacing: Space.sm) {
                    toggle(.media, "music.note", OnboardingStrings.moduleMedia, OnboardingStrings.moduleMediaDetail)
                    toggle(.shelf, "tray", OnboardingStrings.moduleShelf, OnboardingStrings.moduleShelfDetail)
                    toggle(.calendar, "calendar", OnboardingStrings.moduleCalendar, OnboardingStrings.moduleCalendarDetail)
                    toggle(.widgets, "square.grid.2x2", OnboardingStrings.moduleWidgets, OnboardingStrings.moduleWidgetsDetail)
                }
            }
        }
    }

    private func section<C: View>(symbol: String, title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(AuraColor.accent.color).accessibilityHidden(true)
            Text(title).font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(AuraColor.primaryText.color)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            VStack(alignment: .leading, spacing: Space.sm) { content() }
                .font(AuraFont.body).foregroundStyle(AuraColor.primaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { titleFocused = true }
    }

    private func note(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(AuraColor.accent.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AuraFont.body.weight(.semibold))
                Text(body).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ m: NotchModule, _ symbol: String, _ name: String, _ detail: String) -> some View {
        let on = Binding(get: { !store.settings.disabledModules.contains(m) }, set: { store.setModule(m, enabled: $0) })
        return HStack(spacing: Space.md) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(AuraColor.accent.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(AuraFont.body)
                Text(detail).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            Spacer(minLength: Space.md)
            Toggle("", isOn: on).labelsHidden().toggleStyle(.checkbox) // las casillas entran en el anillo de teclado; .switch no (auditoría de accesibilidad)
                .accessibilityLabel(name).accessibilityHint(detail)
        }
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(AuraColor.elevatedSurface.color))
    }

    // MARK: Pie

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Button(step.isLast ? OnboardingStrings.close : OnboardingStrings.skip, action: onFinish)
                .buttonStyle(AuraButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityHint(OnboardingStrings.skipHint)
            Spacer()
            if let prev = step.previous {
                Button(OnboardingStrings.back) { step = prev }.buttonStyle(AuraButtonStyle(emphasis: .primary))
            }
            Button(step.isLast ? OnboardingStrings.start : OnboardingStrings.continue) {
                if let next = step.next { step = next } else { onFinish() }
            }
            .buttonStyle(AuraButtonStyle(emphasis: .filled))
            .keyboardShortcut(.defaultAction)
        }
    }
}
