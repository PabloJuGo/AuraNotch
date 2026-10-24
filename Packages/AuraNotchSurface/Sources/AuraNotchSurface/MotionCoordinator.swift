import AppKit
import QuartzCore
import AuraCore

/// Fuente de fotogramas inyectable. Solo corre mientras hay animación (regla §4.2.4).
@MainActor public protocol MotionClock: AnyObject {
    var now: TimeInterval { get }
    func start(_ tick: @escaping @MainActor () -> Void)
    func stop()
}

/// Reloj real: `CADisplayLink` de la pantalla (macOS 14+), creado al empezar y destruido al terminar.
@MainActor public final class DisplayLinkClock: NSObject, MotionClock {
    private var link: CADisplayLink?
    private var timer: Timer?
    private var tick: (@MainActor () -> Void)?
    public var screen: () -> NSScreen? = { NSScreen.main ?? NSScreen.screens.first }

    public override init() { super.init() }
    public var now: TimeInterval { CACurrentMediaTime() }

    public func start(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        guard link == nil, timer == nil else { return }
        if let l = screen()?.displayLink(target: self, selector: #selector(step)) {
            l.add(to: .main, forMode: .common); link = l
        } else { // sin pantalla: respaldo a 60 Hz, solo mientras anima
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick?() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    public func stop() {
        link?.invalidate(); link = nil
        timer?.invalidate(); timer = nil
        tick = nil
    }

    @objc private func step(_ l: CADisplayLink) { tick?() }
}

/// Fuente única del progreso de transición (0 = compacto, 1 = expandido).
///
/// Muelle críticamente amortiguado resuelto de forma analítica: sin overshoot, independiente de la
/// tasa de refresco y reorientable conservando posición Y velocidad (sin saltos). Ver ADR 0002.
@MainActor public final class MotionCoordinator {
    public private(set) var progress: Double = 0
    public private(set) var target: Double = 0
    public var isAnimating: Bool { running }

    /// Progreso en cada fotograma (y una vez al asentarse).
    public var onProgress: ((Double) -> Void)?
    /// Se llama UNA vez por animación que llega a su destino; una animación reorientada no la emite.
    public var onFinished: ((_ expanded: Bool) -> Void)?

    /// Preferencia de la app (ajustes). Se combina con la del sistema: gana la más restrictiva.
    public var appPreference: MotionPreference = .full
    public var systemReduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    public var preference: MotionPreference {
        let sys: MotionPreference = systemReduceMotion() ? .reduced : .full
        func rank(_ p: MotionPreference) -> Int { switch p { case .full: 0; case .reduced: 1; case .none: 2 } }
        return rank(appPreference) >= rank(sys) ? appPreference : sys
    }

    private let clock: MotionClock
    private var running = false
    // Estado del muelle: e(t) = (A + B·dt)·exp(-ω·dt), con e = progreso - destino.
    private var t0: TimeInterval = 0
    private var a = 0.0, b = 0.0, omega = 1.0
    private var velocity = 0.0

    /// Fracción del recorrido que se da por completada y velocidad residual aceptada.
    static let positionEpsilon = 0.002, velocityEpsilon = 0.1
    /// ω·duración nominal: con 7.5 el error cae por debajo de ~0.5 % a la duración del catálogo.
    static let settleFactor = 7.5

    public init(clock: MotionClock) { self.clock = clock }

    /// Inicia o REORIENTA la animación desde el valor y la velocidad actuales.
    public func animate(toExpanded expanded: Bool, _ transition: AuraCore.Transition) {
        let newTarget = expanded ? 1.0 : 0.0
        let duration = transition.duration(for: preference)
        guard duration > 0 else { snap(toExpanded: expanded, notify: true); return }
        if !running, progress == newTarget { target = newTarget; onFinished?(expanded); return }
        if running { // sincroniza posición/velocidad a "ahora" antes de reorientar
            let s = sample(); velocity = s.v; progress = min(max(target + s.e, 0), 1)
        }
        target = newTarget
        omega = Self.settleFactor / duration
        let e0 = progress - newTarget
        a = e0; b = velocity + omega * e0; t0 = clock.now
        if !running { running = true; clock.start { [weak self] in self?.tick() } }
    }

    /// Salto instantáneo; cancela cualquier animación en curso sin emitir `onFinished`.
    public func snap(toExpanded expanded: Bool) { snap(toExpanded: expanded, notify: false) }

    private func snap(toExpanded expanded: Bool, notify: Bool) {
        stopClock()
        target = expanded ? 1 : 0; progress = target; velocity = 0
        onProgress?(progress)
        if notify { onFinished?(expanded) }
    }

    private func stopClock() {
        if running { clock.stop() }
        running = false
    }

    private func sample() -> (e: Double, v: Double) {
        let dt = max(0, clock.now - t0), decay = exp(-omega * dt)
        return ((a + b * dt) * decay, (b - omega * (a + b * dt)) * decay)
    }

    private func tick() {
        guard running else { return }
        let (e, v) = sample()
        if abs(e) < Self.positionEpsilon, abs(v) < Self.velocityEpsilon {
            snap(toExpanded: target == 1, notify: true)
        } else {
            velocity = v
            progress = min(max(target + e, 0), 1) // acota: overshoot ≈ 0 también ante velocidades heredadas
            onProgress?(progress)
        }
    }
}
