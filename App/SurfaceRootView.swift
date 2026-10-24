import SwiftUI
import QuartzCore
import AuraCore
import AuraDesignSystem
import AuraNotchSurface
import AuraShelf
import AuraMedia
import AuraWidgets
import AuraCalendar
import AuraHome
import AuraClipboard
import AuraAlerts

/// Puente entre el controlador de ventana (CORE) y las vistas del design system (DESIGN).
/// Es el único sitio que conoce a ambos; las vistas siguen siendo funciones puras de props.
@MainActor final class SurfaceBridge {
    weak var surface: SurfaceWindowController?
    var onOpenSettings: () -> Void = {}
    var shelf: ShelfService?
    var media: MediaService?
    var timer: TimerService?
    var battery: BatteryService?
    var widgets: WidgetRegistry?
    var calendar: CalendarService?
    var alerts: AlertCenter?
    var clipboard: ClipboardService?
    var modules: () -> [NotchModule] = { NotchModule.allCases }
    var showCompactTitle: () -> Bool = { true }
    var accent: () -> AccentTheme = { .system }

    /// Texto breve del compacto; el del temporizador depende de la hora, por eso recibe la fecha.
    /// Los avisos siempre llevan su texto; canción y temporizador solo con `showCompactTitle`.
    func compactDetail(at date: Date) -> String? {
        if let text = alerts?.current?.text { return text }
        guard showCompactTitle() else { return nil }
        return timer?.compactInfo(at: date)?.detail ?? media?.compactInfo?.detail
    }
    var timerIsRunning: Bool { if case .running = timer?.phase { true } else { false } }
    /// Alto del notch físico (en modo flotante no hay zona que reservar).
    var topInset: CGFloat { surface?.layout?.mode == .notch ? surface?.layout?.idle.height ?? 0 : 0 }
    var centerGap: CGFloat { surface?.layout?.mode == .notch ? surface?.layout?.idle.width ?? 0 : 0 }
}

struct SurfaceRootView: View {
    let model: SurfaceViewModel
    let bridge: SurfaceBridge
    @State private var lastModule: NotchModule = .home

    /// Color del tema; `nil` con el tema «Sistema» (se deja el acento de macOS).
    private var accentOverride: Color? { let t = bridge.accent(); return t == .system ? nil : t.color }

    private var activeModule: NotchModule? {
        switch model.state {
        case .expanding(let m), .expanded(let m): m
        default: nil
        }
    }

    var body: some View {
        let r = model.shapeRect
        let _ = traceFrame(model, r)
        let p = model.motion == .full ? model.progress : (model.progress >= 0.5 ? 1 : 0)
        // AN-02: el contenido entra después del contenedor y se retira antes (AN-03).
        let expandedOpacity = max(0, min(1, (p - 0.55) / 0.45))
        let compactOpacity = max(0, min(1, 1 - p * 3))
        let shape = NotchShape(topRadius: 6 + 8 * p, bottomRadius: 10 + (Radius.panel - 10) * p)

        ZStack(alignment: .top) {
            shape.fill(AuraColor.surface.color)
            if compactOpacity > 0 {
                // Refresco de 1 s SOLO mientras el temporizador corre; en reposo no hay ticks (§4.2.4).
                Group {
                    if bridge.timerIsRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in compact(at: ctx.date) }
                    } else {
                        compact(at: .now)
                    }
                }
                .opacity(compactOpacity)
            }
            // Contenido siempre vivo y oculto: crearlo a mitad de la apertura costaba ~3 fotogramas (medido).
            do {
                ExpandedChrome(module: lastModule, modules: bridge.modules(), topInset: bridge.topInset,
                               onSelect: { bridge.surface?.send(.selectModule($0)) },
                               onOpenSettings: { bridge.onOpenSettings() }) {
                    moduleContent(lastModule)
                }
                .frame(width: model.expandedFrame.width, height: model.expandedFrame.height, alignment: .top)
                .frame(width: r.width, height: r.height, alignment: .top)
                .environment(\.auraPanelOpen, expandedOpacity > 0.01)
                .opacity(expandedOpacity)
                .allowsHitTesting(p >= 1)
                .accessibilityHidden(expandedOpacity < 0.01)
            }
        }
        .clipShape(shape)
        .environment(\.auraAccent, accentOverride)
        .tint(accentOverride)
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onChange(of: activeModule) { _, m in if let m { lastModule = m } }
        .onAppear { if let m = activeModule { lastModule = m } }
    }

    @ViewBuilder private func moduleContent(_ m: NotchModule) -> some View {
        if m == .home {
            // Servicios de módulos desactivados → nil (Inicio no muestra su tarjeta).
            let on = Set(bridge.modules())
            HomeView(media: on.contains(.media) ? bridge.media : nil, timer: on.contains(.widgets) ? bridge.timer : nil,
                     calendar: on.contains(.calendar) ? bridge.calendar : nil, shelf: on.contains(.shelf) ? bridge.shelf : nil,
                     battery: on.contains(.widgets) ? bridge.battery : nil,
                     clipboard: on.contains(.clipboard) ? bridge.clipboard : nil,
                     onNavigate: { bridge.surface?.send(.selectModule($0)) })
        }
        else if m == .shelf, let shelf = bridge.shelf { ShelfView(service: shelf) }
        else if m == .media, let media = bridge.media { MediaView(service: media) }
        else if m == .widgets, let widgets = bridge.widgets { WidgetsView(registry: widgets) }
        else if m == .calendar, let calendar = bridge.calendar { CalendarView(service: calendar) }
        else if m == .clipboard, let clipboard = bridge.clipboard { ClipboardView(service: clipboard) }
        else { ModulePlaceholder(module: m) }
    }

    private func compact(at date: Date) -> some View {
        CompactContent(activity: compactActivity, detail: bridge.compactDetail(at: date), centerGap: bridge.centerGap)
    }

    private var compactActivity: ActivityKind? {
        if case .compact(let a) = model.state { a } else { nil }
    }
}

/// Contenido provisional por módulo hasta que FEATURES entregue los reales (Sprints 2–4).
private struct ModulePlaceholder: View {
    let module: NotchModule
    var body: some View {
        EmptyStateView(symbol: module.symbolName, title: Strings.moduleTitle(module),
                       message: String(localized: "Este módulo aún no está disponible."))
    }
}

/// Herramienta de desarrollo: `AURA_TRACE=1` imprime (hora, progreso, alto, estado) por fotograma.
private let tracingEnabled = ProcessInfo.processInfo.environment["AURA_TRACE"] != nil

@MainActor func traceFrame(_ model: SurfaceViewModel, _ r: CGRect) {
    guard tracingEnabled else { return }
    FileHandle.standardError.write(Data(String(format: "TRACE %.4f %.3f %.1f %@\n", CACurrentMediaTime(), model.progress, r.height, "\(model.state)").utf8))
}
