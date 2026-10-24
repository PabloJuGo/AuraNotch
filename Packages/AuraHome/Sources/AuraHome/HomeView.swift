import AppKit
import AuraCalendar
import AuraClipboard
import AuraCore
import AuraDesignSystem
import AuraMedia
import AuraShelf
import AuraWidgets
import SwiftUI

/// UI-05 · Inicio: resumen contextual y silencioso. Solo muestra lo que tiene contenido; sin nada relevante,
/// fecha grande y un saludo discreto. Pura función de los servicios (todos opcionales: módulo desactivado = nil).
/// No pide permisos ni carga datos; sin timers propios: el reloj del temporizador es un `TimelineView` de 1 s
/// que solo existe mientras el temporizador corre y la vista está visible.
public struct HomeView: View {
    let media: MediaService?, timer: TimerService?, calendar: CalendarService?
    let shelf: ShelfService?, battery: BatteryService?, clipboard: ClipboardService?
    let now: () -> Date
    let onNavigate: (NotchModule) -> Void

    @State private var visible = false
    @Environment(\.auraPanelOpen) private var panelOpen
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    public init(media: MediaService? = nil, timer: TimerService? = nil, calendar: CalendarService? = nil,
                shelf: ShelfService? = nil, battery: BatteryService? = nil, clipboard: ClipboardService? = nil,
                now: @escaping () -> Date = Date.init, onNavigate: @escaping (NotchModule) -> Void) {
        self.media = media; self.timer = timer; self.calendar = calendar; self.shelf = shelf; self.battery = battery
        self.clipboard = clipboard
        self.now = now; self.onNavigate = onNavigate
    }

    private var inputs: HomeInputs {
        HomeInputs(media: media, timer: timer, calendar: calendar, shelf: shelf, battery: battery, clipboard: clipboard, now: now())
    }

    public var body: some View {
        let cards = HomeModel.cards(inputs)
        Group {
            if cards.isEmpty { quiet } else { summary(cards) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.animation(.switchModule, motion), value: cards)
        .onAppear { visible = true; if panelOpen { refreshReadings() } }
        .task { await media?.refreshAuthorization() } // consulta silenciosa (sin diálogo): habilita controles y portada
        .onChange(of: panelOpen) { _, open in if open { refreshReadings() } }
        .onDisappear { visible = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HomeStrings.summary)
    }

    // MARK: Fecha y saludo

    private var dateText: String {
        let f = now().formatted(.dateTime.weekday(.wide).day().month(.wide))
        return f.prefix(1).uppercased() + f.dropFirst()  // solo la inicial: «Miércoles, 14 de octubre»
    }

    private var greeting: String {
        switch HomeModel.greeting(hour: Calendar.current.component(.hour, from: now())) {
        case .morning: HomeStrings.morning
        case .afternoon: HomeStrings.afternoon
        case .evening: HomeStrings.evening
        }
    }

    // MARK: Estado vacío (Quiet by default)

    private var quiet: some View {
        VStack(spacing: Space.xs) {
            Spacer(minLength: 0)
            Text(dateText)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(AuraColor.primaryText.color)
                .accessibilityAddTraits(.isHeader)
            Text(inputs.isLoading ? HomeStrings.loading : greeting)
                .font(AuraFont.body).foregroundStyle(AuraColor.secondaryText.color)
            if let battery { batteryPill(battery).padding(.top, Space.xs) }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .transition(Motion.contentTransition(motion))
    }

    // MARK: Con contenido

    /// Lecturas puntuales (sin listeners) al abrir el panel.
    private func refreshReadings() { timer?.refresh(); battery?.refresh() }

    private func summary(_ cards: [HomeCard]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.md) {
                header
                if cards.contains(.media), let media { mediaCard(media).transition(Motion.contentTransition(motion)) }
                if cards.contains(.timer), let timer { timerCard(timer).transition(Motion.contentTransition(motion)) }
                // Evento y portapapeles comparten fila; si falta uno, el otro ocupa todo el ancho.
                HStack(alignment: .top, spacing: Space.md) {
                    if cards.contains(.event), let calendar { eventsCard(calendar).transition(Motion.contentTransition(motion)) }
                    if cards.contains(.clipboard), let clipboard { clipboardCard(clipboard).transition(Motion.contentTransition(motion)) }
                }
                if cards.contains(.shelf), let shelf { shelfCard(shelf).transition(Motion.contentTransition(motion)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fecha a la izquierda y la batería como pastilla discreta a la derecha.
    private var header: some View {
        HStack {
            Text(dateText).font(AuraFont.body).foregroundStyle(AuraColor.secondaryText.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let battery { batteryPill(battery) }
        }
    }

    @ViewBuilder private func batteryPill(_ b: BatteryService) -> some View {
        if b.state == .ready, let r = b.reading, r.hasBattery {
            let low = b.isLow, pct = r.percent.map(HomeStrings.percent) ?? ""
            let sub = low ? HomeStrings.lowBattery : r.isCharging ? HomeStrings.charging : ""
            HStack(spacing: Space.xs) {
                Image(systemName: r.isCharging ? "battery.100percent.bolt" : low ? "battery.25percent" : "battery.75percent")
                    .foregroundStyle((low ? AuraColor.warning : r.isCharging ? AuraColor.success : AuraColor.secondaryText).color)
                if !pct.isEmpty { Text(pct).font(AuraFont.numeric).foregroundStyle(AuraColor.secondaryText.color) }
            }
            .padding(.horizontal, Space.sm).padding(.vertical, 2)
            .background(Capsule().fill(AuraColor.elevatedSurface.color))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([HomeStrings.battery + " " + pct, sub].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", "))
        }
    }

    // MARK: Tarjetas

    @ViewBuilder private func timerCard(_ t: TimerService) -> some View {
        if t.isRunning && visible && panelOpen {
            // El contenido se vuelve a evaluar cada segundo; la hora se lee del reloj del servicio.
            TimelineView(.periodic(from: .now, by: 1)) { _ in timerRow(t, at: t.now) }
        } else {
            timerRow(t, at: t.now)
        }
    }

    private func timerRow(_ t: TimerService, at date: Date) -> some View {
        let r = t.remaining(at: date), clock = HomeModel.clock(r)
        let finished = t.phase == .finished
        let paused: Bool = { if case .paused = t.phase { true } else { false } }()
        let sub = finished ? HomeStrings.timerDone : paused ? HomeStrings.timerPaused : HomeStrings.timerRunning
        return HomeRow(symbol: "timer", tint: finished ? AuraColor.warning : AuraColor.accent,
                       title: finished ? HomeStrings.timerDone : clock, subtitle: HomeStrings.timer, mono: !finished,
                       label: "\(HomeStrings.timer), \(sub)" + (finished ? "" : ", \(HomeStrings.timerSpoken(HomeModel.spoken(r)))"),
                       hint: HomeStrings.hint(Strings.moduleTitle(.widgets)),
                       onTap: { onNavigate(.widgets) }) {
            if !finished {
                IconButton(symbol: paused ? "play.fill" : "pause.fill", label: paused ? HomeStrings.resume : HomeStrings.pause) {
                    paused ? t.resume() : t.pause()
                }
            }
            IconButton(symbol: "xmark", label: finished ? HomeStrings.dismiss : HomeStrings.cancelTimer) { t.cancel() }
        }
    }

    private func mediaCard(_ m: MediaService) -> some View {
        let item = m.current?.item
        let controls = m.current.map { MediaControls($0.capabilities, isPlaying: $0.item.isPlaying) }
        let playing = item?.isPlaying ?? false
        let title = item?.title ?? ""
        let sub = [item?.artist, playing ? nil : HomeStrings.mediaPaused].compactMap { $0 }.joined(separator: " · ")
        let label = "\(HomeStrings.nowPlaying): \(title)" + (sub.isEmpty ? "" : ", \(sub)")
        return HStack(spacing: Space.md) {
            Button { onNavigate(.media) } label: {
                HStack(spacing: Space.md) {
                    cover(item?.artworkData)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                        Text(sub.isEmpty ? HomeStrings.nowPlaying : sub).font(AuraFont.body)
                            .foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(HomeStrings.hint(Strings.moduleTitle(.media)))
            // Solo con capacidad declarada (si falta permiso, no hay botón: Inicio nunca lo solicita).
            HStack(spacing: Space.xs) {
                if controls?.previous == true { transportButton("backward.fill", HomeStrings.previous, 14) { await m.skip(forward: false) } }
                if controls?.playPause == true {
                    transportButton(playing ? "pause.fill" : "play.fill", playing ? HomeStrings.pause : HomeStrings.play, 20) { await m.togglePlayPause() }
                }
                if controls?.next == true { transportButton("forward.fill", HomeStrings.next, 14) { await m.skip(forward: true) } }
            }
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(AuraColor.elevatedSurface.color))
        .accessibilityElement(children: .contain)
    }

    private func cover(_ data: Data?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control - 4, style: .continuous)
        return Group {
            if let data, let img = NSImage(data: data) { Image(nsImage: img).resizable().scaledToFill() }
            else {
                Image(systemName: "music.note").font(.title3).foregroundStyle(AuraColor.secondaryText.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(AuraColor.pressedSurface.color)
            }
        }
        .frame(width: 52, height: 52).clipShape(shape).accessibilityHidden(true)
    }

    private func transportButton(_ symbol: String, _ label: String, _ size: CGFloat, _ action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: { Image(systemName: symbol).font(.system(size: size, weight: .semibold)) }
            .buttonStyle(TransportButtonStyle())
            .accessibilityLabel(label)
            .help(label)
    }

    /// Eventos de hoy (hasta tres): toda la tarjeta lleva a Calendario.
    @ViewBuilder private func eventsCard(_ c: CalendarService) -> some View {
        let events = HomeModel.todayEvents(state: c.state, events: c.events, now: now())
        if events.isEmpty {
            let text: String = switch c.state {
            case .loading: HomeStrings.calendarLoading
            case .notDetermined, .noPermission, .denied: HomeStrings.calendarNeedsAccess
            case .error: HomeStrings.calendarError
            case .ready, .empty: HomeStrings.noEventsToday
            }
            ListCard(title: HomeStrings.today, symbol: "calendar", label: "\(HomeStrings.today): \(text)",
                     hint: HomeStrings.hint(Strings.moduleTitle(.calendar)), onTap: { onNavigate(.calendar) }) { emptyText(text) }
        } else {
            let spoken = events.map { c.accessibilityLabel($0) }.joined(separator: ". ")
            ListCard(title: HomeStrings.today, symbol: "calendar", label: "\(HomeStrings.today): \(spoken)",
                     hint: HomeStrings.hint(Strings.moduleTitle(.calendar)), onTap: { onNavigate(.calendar) }) {
                ForEach(events, id: \.id) { e in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.displayTitle(e)).font(AuraFont.body).foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                        Text(c.when(e)).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Últimas tres copias: pulsar una la vuelve a copiar (no navega).
    @ViewBuilder private func clipboardCard(_ cb: ClipboardService) -> some View {
        let items = Array(cb.items.prefix(3))
        if items.isEmpty {
            ListCard(title: HomeStrings.clipboard, symbol: "doc.on.clipboard", label: nil, hint: nil, onTap: nil) {
                emptyText(HomeStrings.clipboardEmpty)
            }
        } else {
            ListCard(title: HomeStrings.clipboard, symbol: "doc.on.clipboard", label: nil, hint: nil, onTap: nil) {
                ForEach(items) { item in
                    Button { cb.copy(item.id) } label: {
                        Text(Self.summary(of: item)).font(AuraFont.body).foregroundStyle(AuraColor.primaryText.color)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.summary(of: item))
                    .accessibilityHint(HomeStrings.clipboardCopyHint)
                }
            }
        }
    }

    static func summary(of item: ClipboardItem) -> String {
        switch item.content {
        case .text(let s): s.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? s
        case .url(let u): u.host ?? u.absoluteString
        case .image: HomeStrings.clipboardImage()
        }
    }

    /// Estantería: nombres de los últimos elementos; toda la tarjeta lleva a ella.
    private func shelfCard(_ s: ShelfService) -> some View {
        let text = HomeStrings.shelfCount(s.items.count)
        let names = s.items.suffix(3).reversed().map(\.name).joined(separator: " · ")
        return ListCard(title: HomeStrings.shelf, symbol: "tray.full", label: s.items.isEmpty ? HomeStrings.shelfEmpty : text,
                        hint: HomeStrings.hint(Strings.moduleTitle(.shelf)), onTap: { onNavigate(.shelf) }) {
            if s.items.isEmpty { emptyText(HomeStrings.shelfEmpty) }
            else {
                Text(names).font(AuraFont.body).foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Texto de estado de una tarjeta sin contenido.
    private func emptyText(_ s: String) -> some View {
        Text(s).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tarjeta con título e icono arriba y contenido debajo. Con `onTap` es un único botón de navegación.
private struct ListCard<Content: View>: View {
    let title: String, symbol: String, label: String?, hint: String?, onTap: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.auraAccent) private var accent

    var body: some View {
        let box = VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).foregroundStyle(accent ?? AuraColor.accent.color)
                Text(title).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            .accessibilityHidden(label != nil)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill((hovering && onTap != nil ? AuraColor.pressedSurface : AuraColor.elevatedSurface).color))
        .onHover { hovering = $0 }
        if let onTap {
            Button(action: onTap) { box.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label ?? title)
                .accessibilityHint(hint ?? "")
        } else {
            box.accessibilityElement(children: .contain).accessibilityLabel(title)
        }
    }
}

// MARK: - Componentes

/// Fila de tarjeta: botón de navegación (icono + texto) y acciones propias a la derecha, fuera del botón.
private struct HomeRow<Actions: View>: View {
    let symbol: String, tint: TokenColor, title: String, subtitle: String?
    var mono = false
    let label: String, hint: String, onTap: () -> Void
    @ViewBuilder let actions: Actions
    @State private var hovering = false
    @Environment(\.auraAccent) private var accent

    init(symbol: String, tint: TokenColor, title: String, subtitle: String?, mono: Bool = false, label: String, hint: String,
         onTap: @escaping () -> Void, @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol; self.tint = tint; self.title = title; self.subtitle = subtitle; self.mono = mono
        self.label = label; self.hint = hint; self.onTap = onTap; self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: onTap) {
                HStack(spacing: Space.md) {
                    Image(systemName: symbol).font(.title3).foregroundStyle(tint == AuraColor.accent ? accent ?? tint.color : tint.color).frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(mono ? .system(.title3, design: .rounded).weight(.semibold).monospacedDigit() : AuraFont.body)
                            .foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                        if let subtitle {
                            Text(subtitle).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(AuraButtonStyle())
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            actions
        }
        .padding(.horizontal, Space.xs).padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill((hovering ? AuraColor.pressedSurface : AuraColor.elevatedSurface).color))
        .onHover { hovering = $0 }
    }
}

private struct IconButton: View {
    let symbol: String, label: String, action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.callout.weight(.semibold)).frame(width: 20, height: 20) }
            .buttonStyle(AuraButtonStyle(emphasis: .primary))
            .accessibilityLabel(label)
            .help(label)
    }
}
