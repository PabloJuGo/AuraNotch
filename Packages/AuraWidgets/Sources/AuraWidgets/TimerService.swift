import AuraCore
import AuraDesignSystem
import Foundation
import Observation
import SwiftUI

public enum TimerPhase: Equatable, Sendable {
    case idle
    case running(end: Date)
    case paused(remaining: TimeInterval)
    case finished
}

/// Aviso al terminar. El widget NUNCA habla con el sistema: lo hace el notifier inyectado (ver `SystemTimerNotifier`).
@MainActor public protocol TimerNotifier: AnyObject {
    func timerFinished(duration: TimeInterval)
    /// Al iniciar una ejecución nueva (no al reanudar): momento contextual para pedir permiso de notificaciones.
    func timerStarted(duration: TimeInterval)
    /// true solo si este notifier solicita/usa de verdad notificaciones del sistema (alimenta `manifest.permissions`).
    var usesSystemNotifications: Bool { get }
}
public extension TimerNotifier {
    func timerStarted(duration: TimeInterval) {}
    var usesSystemNotifications: Bool { false }
}

/// Análogo a `MediaCompactInfo`: alimenta `ActivityKind.timer` y `CompactContent(detail:)`.
public struct TimerCompactInfo: Equatable, Sendable {
    public var activity: ActivityKind
    public var detail: String
    public var accessibilityLabel: String
}

/// Temporizador basado en el INSTANTE DE FIN (no cuenta ticks): sobrevive a sleep/wake y a vistas ocultas.
/// Sin polling: una sola espera de un disparo hasta el fin (ContinuousClock sigue avanzando dormido);
/// la vista refresca cada 1 s con TimelineView solo mientras corre y está visible.
@MainActor @Observable
public final class TimerService: AuraWidget {
    public static let minDuration: TimeInterval = 1
    public static let maxDuration: TimeInterval = 24 * 3600

    public private(set) var phase: TimerPhase = .idle
    /// Duración configurada de la ejecución actual/próxima.
    public private(set) var duration: TimeInterval = 300

    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var waiter: Task<Void, Never>?
    @ObservationIgnored public var onFinished: ((TimeInterval) -> Void)?
    @ObservationIgnored public weak var notifier: (any TimerNotifier)?

    public init(clock: @escaping @Sendable () -> Date = { Date() }, duration: TimeInterval = 300) {
        self.clock = clock
        self.duration = Self.clamp(duration)
    }

    // MARK: AuraWidget
    /// `.notifications` solo si el notifier inyectado de verdad las solicita.
    public var manifest: WidgetManifest {
        WidgetManifest(id: "timer", name: WidgetStrings.timerName, symbol: "timer", preferredSize: .wideTall,
                       permissions: notifier?.usesSystemNotifications == true ? [.notifications] : [],
                       actions: [.init(id: "start", title: WidgetStrings.start), .init(id: "pause", title: WidgetStrings.pause),
                                 .init(id: "cancel", title: WidgetStrings.cancel)])
    }
    public var state: WidgetState { .ready }
    public func setActive(_ active: Bool) {}  // la espera hasta el fin sigue viva aunque no sea visible (una sola espera, no un timer periódico)
    public func makeBody() -> AnyView { AnyView(TimerView(service: self)) }
    public var summary: String {
        let phaseName: String
        switch phase {
        case .idle: phaseName = WidgetStrings.idle
        case .running: phaseName = WidgetStrings.running
        case .paused: phaseName = WidgetStrings.paused
        case .finished: return WidgetStrings.finished
        }
        return WidgetStrings.timerSummary(phaseName, WidgetStrings.spoken(remaining(at: clock())))
    }

    // MARK: Consultas
    public func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: duration
        case .running(let end): max(0, end.timeIntervalSince(date))
        case .paused(let r): r
        case .finished: 0
        }
    }
    /// 0…1 transcurrido de la ejecución.
    public func progress(at date: Date) -> Double {
        switch phase {
        case .idle: 0
        case .finished: 1
        default: min(1, max(0, 1 - remaining(at: date) / duration))
        }
    }
    /// Hora según el reloj inyectado.
    public var now: Date { clock() }
    public var isRunning: Bool { if case .running = phase { true } else { false } }

    // MARK: Acciones
    /// Solo con el temporizador parado (idle/finished); si no, se ignora.
    public func setDuration(_ seconds: TimeInterval) {
        switch phase {
        case .idle, .finished: duration = Self.clamp(seconds); phase = .idle
        default: return
        }
    }
    public func start() {
        switch phase {
        case .idle, .finished: begin(after: duration); notifier?.timerStarted(duration: duration)
        case .paused: resume()
        case .running: return
        }
    }
    public func pause() {
        refresh()
        guard case .running(let end) = phase else { return }
        waiter?.cancel()
        phase = .paused(remaining: max(0, end.timeIntervalSince(clock())))
    }
    public func resume() {
        guard case .paused(let r) = phase else { return }
        begin(after: r)
    }
    public func cancel() {
        waiter?.cancel()
        phase = .idle
    }
    /// Comprueba el reloj. Lo llaman la espera de un disparo, la vista al aparecer y el host tras un wake.
    public func refresh() {
        guard case .running(let end) = phase, clock() >= end else { return }
        waiter?.cancel()
        phase = .finished
        onFinished?(duration)
        notifier?.timerFinished(duration: duration)
    }
    public func retry() {}

    // MARK: Compacto
    public var compactInfo: TimerCompactInfo? { compactInfo(at: clock()) }
    /// nil = sin actividad. El host debe volver a pedirlo cada segundo SOLO mientras el compacto muestre el temporizador.
    public func compactInfo(at date: Date) -> TimerCompactInfo? {
        switch phase {
        case .idle: return nil
        case .finished:
            return TimerCompactInfo(activity: .timer, detail: WidgetStrings.finished,
                                    accessibilityLabel: "\(WidgetStrings.timerName): \(WidgetStrings.finished)")
        case .running, .paused:
            let r = remaining(at: date)
            return TimerCompactInfo(activity: .timer, detail: TimerFormat.clock(r),
                                    accessibilityLabel: "\(WidgetStrings.timerName): \(WidgetStrings.spoken(r))")
        }
    }

    // MARK: Interno
    private static func clamp(_ s: TimeInterval) -> TimeInterval { min(maxDuration, max(minDuration, s)) }

    private func begin(after interval: TimeInterval) {
        phase = .running(end: clock().addingTimeInterval(interval))
        waiter?.cancel()
        waiter = Task { [weak self] in
            // Reintenta si el reloj cambió (p. ej. wake) y la espera terminó antes/después de lo previsto.
            while let wait = self?.secondsToEnd(), !Task.isCancelled {
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if Task.isCancelled { return }
                self?.refresh()
                if wait <= 0 { return }
            }
        }
    }
    private func secondsToEnd() -> TimeInterval? {
        guard case .running(let end) = phase else { return nil }
        return end.timeIntervalSince(clock())
    }
}

enum TimerFormat {
    /// m:ss o h:mm:ss, redondeando hacia arriba (5:00 al iniciar, 0:00 solo al terminar).
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Vista (UI-10)

public struct TimerView: View {
    let service: TimerService
    @State private var visible = false
    @Environment(\.auraPanelOpen) private var panelOpen
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    public init(service: TimerService) { self.service = service }

    public var body: some View {
        content
            .animation(Motion.animation(.timerFinished, motion), value: service.phase)
            .onAppear { visible = true; service.refresh() }
            .onDisappear { visible = false }
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        switch service.phase {
        case .idle: idle
        case .running, .paused: counting
        case .finished: finished
        }
    }

    private var bigFont: Font { .system(.title, design: .rounded).weight(.semibold).monospacedDigit() }

    private var idle: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                iconButton("minus", WidgetStrings.lessTime) { service.setDuration(max(60, service.duration - 60)) }
                Text(TimerFormat.clock(service.duration)).font(bigFont).foregroundStyle(AuraColor.primaryText.color)
                    .accessibilityLabel(WidgetStrings.durationLabel)
                    .accessibilityValue(WidgetStrings.spoken(service.duration))
                iconButton("plus", WidgetStrings.moreTime) { service.setDuration(service.duration + 60) }
                Spacer(minLength: 0)
                Button(WidgetStrings.start) { service.start() }.buttonStyle(AuraButtonStyle(emphasis: .filled)).lineLimit(1).fixedSize()
            }
            HStack(spacing: Space.xs) {
                ForEach([1, 5, 10, 25], id: \.self) { m in
                    Button(WidgetStrings.minutes(m)) { service.setDuration(Double(m) * 60) }
                        .buttonStyle(AuraButtonStyle(emphasis: .secondary)).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var counting: some View {
        let running = service.isRunning
        return VStack(alignment: .leading, spacing: Space.sm) {
            // Se refresca cada 1 s solo si corre y es visible; pausado/oculto = vista estática, sin reloj.
            TimelineView(.animation(minimumInterval: 1, paused: !(running && visible && panelOpen))) { ctx in
                let _ = ctx.date  // solo dispara el redibujado; la hora sale del reloj del servicio (una única fuente)
                let r = service.remaining(at: service.now)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(TimerFormat.clock(r)).font(bigFont).foregroundStyle(AuraColor.primaryText.color)
                    TimerBar(fraction: service.progress(at: service.now))
                }
                .accessibilityRepresentation {
                    ProgressView(value: service.progress(at: service.now))
                        .accessibilityLabel(WidgetStrings.remainingLabel)
                        .accessibilityValue(WidgetStrings.spoken(r))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            HStack(spacing: Space.sm) {
                Button { running ? service.pause() : service.resume() } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(AuraButtonStyle(emphasis: .primary))
                .accessibilityLabel(running ? WidgetStrings.pause : WidgetStrings.resume).help(running ? WidgetStrings.pause : WidgetStrings.resume)
                iconButton("xmark", WidgetStrings.cancel) { service.cancel() }
                if !running { Text(WidgetStrings.paused).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color) }
                Spacer(minLength: 0)
            }
        }
    }

    /// AN-11: estado final estático (símbolo + texto), sin pulsación ni animación repetida.
    private var finished: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(AuraColor.success.color).accessibilityHidden(true)
                Text(WidgetStrings.finished).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.sm) {
                Button(WidgetStrings.restart) { service.start() }.buttonStyle(AuraButtonStyle(emphasis: .filled))
                Button(WidgetStrings.dismiss) { service.cancel() }.buttonStyle(AuraButtonStyle(emphasis: .secondary))
            }
        }
        .transition(Motion.contentTransition(motion))
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(AuraButtonStyle(emphasis: .primary)).accessibilityLabel(label).help(label)
    }
}

struct TimerBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AuraColor.separator.color)
                Capsule().fill(AuraColor.accent.color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
