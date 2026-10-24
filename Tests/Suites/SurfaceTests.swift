import Foundation
import AppKit
import CoreGraphics
import AuraCore
import AuraNotchSurface

// MARK: - Utilidades

@MainActor final class ManualClock: MotionClock {
    var now: TimeInterval = 0
    private(set) var tick: (@MainActor () -> Void)?
    var isRunning: Bool { tick != nil }
    func start(_ tick: @escaping @MainActor () -> Void) { self.tick = tick }
    func stop() { tick = nil }
    /// Avanza `dt` segundos en pasos de `step` (1/60 por defecto), llamando al tick como lo haría una pantalla.
    func advance(_ dt: TimeInterval, step: TimeInterval = 1.0 / 60) {
        var left = dt
        while left > 1e-12 {
            let s = min(step, left); now += s; left -= s; tick?()
        }
    }
}

/// Mini-controlador de pruebas: máquina + coordinador + temporizadores sobre reloj manual (mismo cableado que el real).
@MainActor final class Harness {
    let clock = ManualClock()
    let motion: MotionCoordinator
    var model = SurfaceModel()
    var ctx = SurfaceContext()
    var timers: [SurfaceTimer: TimeInterval] = [:]
    var lastEffects: [SurfaceEffect] = []
    var maxAnimatesPerStep = 0
    var finishedCount = 0
    private var queue: [SurfaceEvent] = []
    private var draining = false

    init() {
        motion = MotionCoordinator(clock: clock)
        motion.systemReduceMotion = { false }
        motion.onFinished = { [unowned self] _ in finishedCount += 1; send(.transitionFinished) }
    }

    @discardableResult func send(_ e: SurfaceEvent) -> [SurfaceEffect] {
        queue.append(e)
        guard !draining else { return [] }
        draining = true; defer { draining = false }
        var all: [SurfaceEffect] = []
        while !queue.isEmpty {
            let (m, fx) = SurfaceStateMachine.reduce(model, queue.removeFirst(), ctx)
            model = m; all += fx; apply(fx)
        }
        lastEffects = all
        return all
    }

    func fire(_ t: SurfaceTimer) {
        let (m, fx) = SurfaceStateMachine.fire(model, t, ctx)
        model = m; lastEffects = fx; apply(fx)
    }

    private func apply(_ fx: [SurfaceEffect]) {
        maxAnimatesPerStep = max(maxAnimatesPerStep, fx.filter { if case .animate = $0 { true } else { false } }.count)
        for f in fx {
            switch f {
            case .animate(let x, let tr): motion.animate(toExpanded: x, tr)
            case .snap(let x): motion.snap(toExpanded: x)
            case .scheduleTimer(let t, let after): timers[t] = clock.now + after
            case .cancelTimer(let t): timers[t] = nil
            default: break
            }
        }
    }

    /// Avanza tiempo disparando los temporizadores vencidos en orden.
    func advance(_ dt: TimeInterval) {
        let end = clock.now + dt
        while true {
            let due = timers.filter { $0.value <= end }.min { $0.value < $1.value }
            guard let d = due else { break }
            clock.advance(max(0, d.value - clock.now)); timers[d.key] = nil; fire(d.key)
        }
        clock.advance(max(0, end - clock.now))
    }

    func has(_ fx: SurfaceEffect) -> Bool { lastEffects.contains(fx) }
}

/// LCG determinista (sin dependencias de `SystemRandomNumberGenerator`).
struct LCG {
    var s: UInt64
    mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) }
}

extension SelfCheck {
    /// Variante con detalle diagnóstico (solo se evalúa si falla).
    func expect(_ cond: @autoclosure () -> Bool, _ msg: String, _ detail: @autoclosure () -> String, line: UInt = #line) {
        let ok = cond()
        expect(ok, ok ? msg : "\(msg) [\(detail())]", line: line)
    }
}

// MARK: - Suite

@MainActor func runSurfaceSuite(_ t: SelfCheck) {
    geometrySuite(t)
    stateMachineSuite(t)
    motionSuite(t)
    integrationSuite(t)
    fullscreenSuite(t)
    keyboardAndHitRegionSuite(t)
    dragProximitySuite(t)
    swipeSuite(t)
}

// MARK: Geometría

@MainActor private func geometrySuite(_ t: SelfCheck) {
    let notch = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                              visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1073), safeAreaTop: 33.5,
                              auxTopLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
                              auxTopRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5))
    t.expect(notch.notchRect == CGRect(x: 762.5, y: 1073.5, width: 185, height: 33.5), "notchRect real (185 x 33.5)")

    let l = NotchGeometry.layout(for: notch, requested: .notch)
    t.expect(l?.mode == .notch, "notch: modo notch")
    t.expect(l?.idle == CGRect(x: 762.5, y: 1073.5, width: 185, height: 33.5), "notch: idle = hueco del notch")
    t.expect(l?.compact == CGRect(x: 716.5, y: 1073.5, width: 277, height: 33.5), "notch: compacto rodea el notch (+46 por lado)")
    t.expect(l?.expanded == CGRect(x: 555, y: 727, width: 600, height: 380), "notch: expandido (600x380) cuelga del borde superior físico")

    // Áreas auxiliares en coordenadas locales de una pantalla con origen desplazado: mismo resultado, desplazado.
    var shifted = notch
    shifted.frame = shifted.frame.offsetBy(dx: 1920, dy: 0); shifted.visibleFrame = shifted.visibleFrame.offsetBy(dx: 1920, dy: 0)
    t.expect(shifted.notchRect == notch.notchRect?.offsetBy(dx: 1920, dy: 0), "notch con origen desplazado y aux locales")
    var shiftedGlobal = shifted
    shiftedGlobal.auxTopLeft = notch.auxTopLeft?.offsetBy(dx: 1920, dy: 0)
    shiftedGlobal.auxTopRight = notch.auxTopRight?.offsetBy(dx: 1920, dy: 0)
    t.expect(shiftedGlobal.notchRect == shifted.notchRect, "aux locales o globales dan el mismo notchRect")

    // Datos incoherentes -> no hay notch.
    var bad = notch; bad.auxTopRight = CGRect(x: 100, y: 1073.5, width: 100, height: 33.5)
    t.expect(bad.notchRect == nil, "aux incoherentes -> sin notch")

    // Dock inferior grande: el expandido se recorta al área visible.
    var docked = notch; docked.visibleFrame = CGRect(x: 0, y: 900, width: 1710, height: 173)
    let ld = NotchGeometry.layout(for: docked, requested: .notch)
    t.expect(ld?.expanded.minY == 900 && ld?.expanded.maxY == 1107, "notch: expandido recortado por abajo al visibleFrame")

    // Sin notch: flotante top-center bajo la barra de menús.
    let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                              visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055), scale: 1)
    let lp = NotchGeometry.layout(for: plain, requested: .notch)
    t.expect(lp?.mode == .topCenterFloating, "sin notch: .notch cae a flotante")
    t.expect(lp?.expanded == CGRect(x: 660, y: 669, width: 600, height: 380), "flotante: centrado, 6 pt bajo la barra", "\(String(describing: lp?.expanded))")
    t.expect(NotchGeometry.layout(for: plain, requested: .disabledOnExternalDisplay) == nil, "sin notch + disabledOnExternal -> nil")
    t.expect(NotchGeometry.layout(for: notch, requested: .disabledOnExternalDisplay)?.mode == .notch, "con notch + disabledOnExternal -> notch")
    t.expect(NotchGeometry.layout(for: notch, requested: .topCenterFloating)?.mode == .topCenterFloating, "flotante forzado en pantalla con notch")
    t.expect(NotchGeometry.layout(for: notch, requested: .topCenterFloating)?.expanded.maxY == 1073 - 6, "flotante en notch: bajo la barra de menús")

    // Pantalla pequeña: el panel se recorta.
    let small = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                              visibleFrame: CGRect(x: 0, y: 40, width: 400, height: 235), scale: 1)
    let ls = NotchGeometry.layout(for: small, requested: .notch)
    t.expect(ls?.expanded == CGRect(x: 0, y: 40, width: 400, height: 229), "pantalla pequeña: recorte a ancho y alto visibles", "\(String(describing: ls?.expanded))")

    // Dock lateral + monitor con origen negativo.
    let side = ScreenMetrics(frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
                             visibleFrame: CGRect(x: -1800, y: 100, width: 1800, height: 1055), scale: 1)
    let lside = NotchGeometry.layout(for: side, requested: .notch)
    t.expect(lside.map { side.visibleFrame.contains($0.expanded) } ?? false, "origen negativo + dock lateral: dentro del visibleFrame")

    // Pantalla degenerada.
    let tiny = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 100, height: 4), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 4), scale: 1)
    t.expect(NotchGeometry.layout(for: tiny, requested: .notch) == nil, "pantalla sin área útil -> nil")

    // Propiedades sobre una malla de pantallas y modos: contención, mismo borde superior, tamaños positivos.
    var checked = 0
    for w in stride(from: 200, through: 3000, by: 380) {
        for h in stride(from: 150, through: 1700, by: 310) {
            for hasNotch in [false, true] {
                for dock in [0, 60, 140] {
                    for mode: SurfaceMode in [.notch, .topCenterFloating, .disabledOnExternalDisplay] {
                        let fr = CGRect(x: CGFloat(-w / 2), y: 17, width: CGFloat(w), height: CGFloat(h))
                        let vis = CGRect(x: fr.minX, y: fr.minY + CGFloat(dock), width: fr.width, height: fr.height - CGFloat(dock) - 25)
                        var m = ScreenMetrics(frame: fr, visibleFrame: vis, scale: 2)
                        if hasNotch {
                            m.safeAreaTop = 30
                            m.auxTopLeft = CGRect(x: fr.minX, y: fr.maxY - 30, width: fr.width / 2 - 90, height: 30)
                            m.auxTopRight = CGRect(x: fr.midX + 90, y: fr.maxY - 30, width: fr.width / 2 - 90, height: 30)
                        }
                        guard let lay = NotchGeometry.layout(for: m, requested: mode) else { continue }
                        let area = lay.mode == .notch ? CGRect(x: fr.minX, y: vis.minY, width: fr.width, height: fr.maxY - vis.minY) : vis
                        let rects = [lay.idle, lay.compact, lay.expanded]
                        let ok = rects.allSatisfy { area.insetBy(dx: -0.01, dy: -0.01).contains($0) && $0.width > 0 && $0.height > 0 }
                            && Set(rects.map { $0.maxY }).count == 1
                        t.expect(ok, "malla \(w)x\(h) notch=\(hasNotch) dock=\(dock) \(mode): dentro del área y anclado arriba", "\(rects)")
                        checked += 1
                    }
                }
            }
        }
    }
    t.expect(checked > 100, "malla de geometría recorrida (\(checked) casos)")
    t.expect(NotchGeometry.lerp(CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 10, width: 30, height: 30), 1.7).width == 30, "lerp acota progreso > 1")
}

// MARK: Máquina de estados

@MainActor private func stateMachineSuite(_ t: SelfCheck) {
    func run(_ events: [SurfaceEvent], from m: SurfaceModel = SurfaceModel(), ctx: SurfaceContext = SurfaceContext()) -> (SurfaceModel, [SurfaceEffect]) {
        var model = m, fx: [SurfaceEffect] = []
        for e in events { let r = SurfaceStateMachine.reduce(model, e, ctx); model = r.0; fx = r.1 }
        return (model, fx)
    }
    let ctx = SurfaceContext()
    let open = SurfaceEffect.animate(toExpanded: true, .compactToExpanded)
    let close = SurfaceEffect.animate(toExpanded: false, .expandedToCompact)

    // Hover con retraso como efecto, nunca abre directamente.
    var (m, fx) = run([.pointerEnter])
    t.expect(m.state == .idle && fx.contains(.scheduleTimer(.hoverOpen, after: ctx.hoverDelay)), "hover: programa temporizador, no abre")
    (m, fx) = SurfaceStateMachine.fire(m, .hoverOpen, ctx)
    t.expect(m.state == .expanding(.home) && fx.contains(open), "hover: al vencer el retraso abre")
    (m, fx) = SurfaceStateMachine.reduce(m, .transitionFinished, ctx)
    t.expect(m.state == .expanded(.home), "expanding -> expanded al terminar")
    (m, _) = run([.pointerEnter, .pointerExit])
    t.expect(SurfaceStateMachine.fire(m, .hoverOpen, ctx).0.state == .idle, "hover: salir antes del retraso no abre")
    t.expect(run([.pointerEnter, .pointerExit]).1.contains(.cancelTimer(.hoverOpen)), "hover: salir cancela el temporizador")

    // Gracia al salir.
    let expanded = SurfaceModel(state: .expanded(.home))
    (m, fx) = run([.pointerEnter, .pointerExit], from: expanded)
    t.expect(m.state == .expanded(.home) && fx.contains(.scheduleTimer(.hoverClose, after: ctx.closeGrace)), "salir: gracia antes de cerrar")
    t.expect(run([.pointerExit, .pointerEnter], from: expanded).1.contains(.cancelTimer(.hoverClose)), "volver durante la gracia cancela el cierre")
    (m, fx) = SurfaceStateMachine.fire(run([.pointerEnter, .pointerExit], from: expanded).0, .hoverClose, ctx)
    t.expect(m.state == .collapsing && fx.contains(close), "gracia vencida: cierra")
    t.expect(SurfaceStateMachine.fire(run([.pointerExit, .pointerEnter], from: expanded).0, .hoverClose, ctx).0.state == .expanded(.home), "gracia vencida con el puntero dentro: no cierra")

    // Clic / hotkey / escape.
    t.expect(run([.click]).0.state == .expanding(.home), "clic abre")
    var noClick = SurfaceContext(); noClick.openOnClick = false
    t.expect(run([.click], ctx: noClick).0.state == .idle, "clic con openOnClick=false no abre")
    t.expect(run([.click], from: expanded).0.state == .expanded(.home), "clic en expandido: lo gestiona el contenido")
    t.expect(run([.click], from: SurfaceModel(state: .collapsing)).0.state == .expanding(.home), "clic durante colapso reorienta a abrir")
    t.expect(run([.pointerEnter], from: SurfaceModel(state: .collapsing)).0.state == .expanding(.home), "puntero vuelve durante colapso: reabre")
    (m, fx) = run([.hotkey])
    t.expect(m.pinned && m.state == .expanding(.home), "hotkey abre fijado")
    t.expect(run([.hotkey, .pointerEnter, .pointerExit]).1.contains(.scheduleTimer(.hoverClose, after: ctx.closeGrace)) == false, "fijado: salir no programa cierre")
    t.expect(run([.hotkey, .hotkey]).0.state == .collapsing, "hotkey alterna: cierra")
    t.expect(run([.escape], from: expanded).0.state == .collapsing, "escape cierra expandido")
    t.expect(run([.escape], from: SurfaceModel(state: .expanding(.home))).0.state == .collapsing, "escape cierra durante la expansión")
    t.expect(run([.escape]).0.state == .idle, "escape en idle: nada")
    var busy = SurfaceContext(); busy.isInteracting = true
    (m, fx) = run([.escape], from: expanded, ctx: busy)
    t.expect(m.state == .expanded(.home) && fx == [.dismissInteraction], "escape progresivo: primero cierra menú/selección")
    (m, fx) = SurfaceStateMachine.fire(run([.pointerExit], from: expanded).0, .hoverClose, busy)
    t.expect(m.state == .expanded(.home) && fx == [.scheduleTimer(.hoverClose, after: busy.closeGrace)], "no cierra con menú/selección activos (reprograma)")

    // Actividades: nunca fuerzan apertura.
    t.expect(run([.activityChanged(.media(playing: true))]).0.state == .compact(.media(playing: true)), "actividad: idle -> compact")
    t.expect(!run([.activityChanged(.error)]).1.contains(open), "actividad no abre")
    t.expect(run([.activityChanged(.timer), .activityChanged(nil)]).0.state == .idle, "actividad nil -> idle")
    for s in [SurfaceState.expanded(.media), .expanding(.media), .collapsing] {
        let (mm, ff) = run([.activityChanged(.transfer)], from: SurfaceModel(state: s))
        t.expect(mm.state == s && ff.isEmpty, "actividad durante \(s): no altera estado ni anima")
    }
    t.expect(run([.activityChanged(.transfer), .transitionFinished], from: SurfaceModel(state: .collapsing)).0.state == .compact(.transfer), "al terminar el colapso se reposa en la actividad actual")

    // Drag & drop.
    (m, fx) = run([.dragEntered])
    t.expect(m.state == .expanding(.shelf) && m.dragActive && fx.contains(open), "dragEntered abre la shelf sin retraso")
    t.expect(run([.dragEntered, .pointerExit], from: SurfaceModel()).1.contains(.scheduleTimer(.hoverClose, after: ctx.closeGrace)) == false, "drag válido: salir del puntero no cierra")
    t.expect(SurfaceStateMachine.fire(run([.dragEntered, .pointerExit]).0, .hoverClose, ctx).0.state == .expanding(.shelf), "drag válido: el temporizador de cierre no cierra")
    (m, fx) = run([.dragEntered, .dragExited])
    t.expect(fx == [.scheduleTimer(.hoverClose, after: ctx.closeGrace)], "dragExited: cierre con gracia")
    t.expect(run([.dragExited, .dragEntered], from: expanded).1.contains(.cancelTimer(.hoverClose)), "volver a entrar con el drag cancela el cierre")
    (m, fx) = run([.dragEntered], from: SurfaceModel(state: .expanded(.calendar)))
    t.expect(m.state == .expanded(.shelf) && !fx.contains(open) && !fx.contains(close), "drag en otro módulo: cambia a shelf sin animar geometría")
    (m, _) = run([.dragEntered, .transitionFinished, .drop])
    t.expect(m.state == .expanded(.shelf) && !m.dragActive, "drop: queda abierto en shelf")

    // Módulos.
    t.expect(run([.selectModule(.media)], from: expanded).0.state == .expanded(.media), "selectModule en expanded")
    t.expect(run([.selectModule(.media)], from: SurfaceModel(state: .expanding(.home))).0.state == .expanding(.media), "selectModule en expanding no reinicia animación")
    t.expect(run([.selectModule(.calendar), .click]).0.state == .expanding(.calendar), "módulo elegido en reposo se abre al expandir")

    // Transiciones obsoletas.
    t.expect(run([.transitionFinished]).0.state == .idle, "transitionFinished en idle se ignora")
    t.expect(run([.hotkey, .hotkey, .transitionFinished]).0.state == .idle, "abrir->cerrar->finished: reposa en idle")

    // Pantalla / fullscreen / habilitación.
    (m, fx) = run([.screenChanged], from: expanded)
    t.expect(m.state == .collapsing && fx.contains(.updateGeometry), "screenChanged con panel abierto: recalcula y pliega")
    t.expect(run([.screenChanged]).1 == [.updateGeometry], "screenChanged en reposo: solo recalcula")
    (m, fx) = run([.fullscreenChanged(true)], from: expanded)
    t.expect(m.state == .suspended && fx.contains(.hideWindow) && fx.contains(.snap(toExpanded: false)), "fullscreen (hide): suspende y oculta")
    t.expect(run([.pointerEnter, .click, .hotkey, .dragEntered], from: m).0.state == .suspended, "suspendida: ignora entrada")
    (m, fx) = run([.fullscreenChanged(true), .fullscreenChanged(false)], from: expanded)
    t.expect(m.state == .idle && fx.contains(.showWindow), "salir de fullscreen: reaparece plegada")
    var keep = SurfaceContext(); keep.fullscreenPolicy = .keepVisible
    t.expect(run([.fullscreenChanged(true)], from: expanded, ctx: keep).0.state == .expanded(.home), "fullscreen (keepVisible): sin cambios")
    (m, fx) = run([.setEnabled(false)], from: expanded)
    t.expect(m.state == .hidden && fx.contains(.hideWindow) && fx.contains(.cancelTimer(.hoverClose)), "setEnabled(false): oculta y cancela")
    t.expect(run([.pointerEnter, .click, .hotkey, .escape], from: m).0.state == .hidden, "oculta: ignora entrada")
    (m, fx) = run([.activityChanged(.timer), .setEnabled(true)], from: m)
    t.expect(m.state == .compact(.timer) && fx.contains(.showWindow), "setEnabled(true): reaparece con la actividad registrada")
    t.expect(run([.setEnabled(false), .fullscreenChanged(true), .setEnabled(true)]).0.state == .suspended, "habilitar durante fullscreen: suspendida")
    t.expect(run([.permissionChanged], from: expanded).0 == expanded, "permissionChanged no altera la máquina")
}

// MARK: Movimiento

@MainActor private func motionSuite(_ t: SelfCheck) {
    let d = AuraCore.Transition.compactToExpanded.duration
    func make() -> (MotionCoordinator, ManualClock, Recorder) {
        let clock = ManualClock(), mc = MotionCoordinator(clock: clock), rec = Recorder()
        mc.systemReduceMotion = { false }
        mc.onProgress = { rec.samples.append($0) }
        mc.onFinished = { rec.finished.append($0) }
        return (mc, clock, rec)
    }

    // Apertura completa: monótona, sin overshoot, termina cerca de la duración, reloj parado en reposo.
    var (mc, clock, rec) = make()
    mc.animate(toExpanded: true, .compactToExpanded)
    t.expect(clock.isRunning && mc.isAnimating, "al animar el reloj corre")
    clock.advance(d * 1.4)
    t.expect(rec.samples.allSatisfy { $0 >= 0 && $0 <= 1 }, "progreso dentro de 0…1")
    t.expect(zip(rec.samples, rec.samples.dropFirst()).allSatisfy { $1 >= $0 }, "apertura monótona")
    t.expect(mc.progress == 1 && rec.finished == [true], "termina exactamente en 1 y notifica una vez")
    t.expect(!clock.isRunning && !mc.isAnimating, "en reposo no hay reloj")
    t.expect((rec.samples.count - 1) <= Int(d * 1.3 * 60) + 1, "asienta en ≤ 1.3× la duración del catálogo (\(rec.samples.count - 1) fotogramas)")

    // Independencia de la tasa de refresco.
    func progressAt(_ t0: TimeInterval, step: TimeInterval) -> Double {
        let (m, c, _) = make(); m.animate(toExpanded: true, .compactToExpanded); c.advance(t0, step: step); return m.progress
    }
    let p30 = progressAt(0.1, step: 1.0 / 30), p60 = progressAt(0.1, step: 1.0 / 60), p120 = progressAt(0.1, step: 1.0 / 120)
    t.expect(abs(p30 - p60) < 1e-9 && abs(p60 - p120) < 1e-9, "mismo progreso a 30/60/120 Hz (\(p30), \(p60), \(p120))")

    // Reorientación sin saltos ni velocidad nueva.
    (mc, clock, rec) = make()
    mc.animate(toExpanded: true, .compactToExpanded)
    clock.advance(0.07)
    let before = mc.progress, lastStep = rec.samples[rec.samples.count - 1] - rec.samples[rec.samples.count - 2]
    mc.animate(toExpanded: false, .expandedToCompact)
    t.expect(abs(mc.progress - before) < 1e-12, "reorientar en el mismo instante no salta")
    let n = rec.samples.count
    clock.advance(1.0 / 60)
    let firstStep = abs(rec.samples[n] - before)
    t.expect(firstStep <= abs(lastStep) * 1.05 + 1e-9, "reorientar no inyecta velocidad nueva (\(firstStep) vs \(lastStep))")
    clock.advance(1)
    t.expect(rec.finished == [false] && mc.progress == 0, "la animación reorientada notifica solo el destino final")
    t.expect(rec.samples.allSatisfy { $0 >= 0 && $0 <= 1 }, "reorientar: sin overshoot fuera de 0…1")

    // Destino actual / snap.
    (mc, clock, rec) = make()
    mc.animate(toExpanded: false, .expandedToCompact)
    t.expect(rec.finished == [false] && !clock.isRunning, "animar al valor actual notifica y no arranca reloj")
    mc.animate(toExpanded: true, .compactToExpanded); clock.advance(0.05)
    mc.snap(toExpanded: false)
    t.expect(mc.progress == 0 && !clock.isRunning && rec.finished == [false], "snap cancela sin notificar")

    // Reduce Motion: sistema + app, la más restrictiva.
    (mc, clock, rec) = make()
    mc.systemReduceMotion = { true }
    t.expect(mc.preference == .reduced, "sistema Reduce Motion -> .reduced")
    mc.appPreference = .none
    t.expect(mc.preference == .none, "app .none gana sobre sistema .reduced")
    mc.appPreference = .full
    mc.animate(toExpanded: true, .compactToExpanded); clock.advance(0.2)
    t.expect(mc.progress == 1 && rec.finished == [true], "Reduce Motion: asienta en ≤0.2 s (duración ≤120 ms)")
    mc.appPreference = .none
    mc.animate(toExpanded: false, .expandedToCompact)
    t.expect(mc.progress == 0 && rec.finished == [true, false] && !clock.isRunning, "preferencia .none: instantáneo y síncrono")
}

@MainActor private final class Recorder { var samples: [Double] = []; var finished: [Bool] = [] }

// MARK: Integración máquina + movimiento

@MainActor private func integrationSuite(_ t: SelfCheck) {
    // Coherencia lógico/visual: el estado de la máquina y el destino del coordinador no divergen.
    func consistent(_ h: Harness) -> Bool {
        let m = h.motion
        switch h.model.state {
        case .expanding: return m.target == 1
        case .collapsing: return m.target == 0
        case .expanded: return m.target == 1 && m.progress == 1 && !m.isAnimating
        case .idle, .compact, .hidden, .suspended: return m.target == 0 && m.progress == 0 && !m.isAnimating
        }
    }

    // 100 ciclos abrir->cerrar->abrir interrumpidos a distintos puntos.
    let h = Harness()
    var ok = true
    for i in 0..<100 {
        h.send(.click)
        h.advance([0, 0.01, 0.05, 0.1, 0.2][i % 5])
        h.send(.hotkey)          // cierra (o abre, si ya estaba cerrando)
        h.advance([0.03, 0, 0.12, 0.01, 0.3][i % 5])
        h.send(.click)           // reabre en pleno colapso
        h.advance([0.02, 0.07, 0, 0.15, 0.01][i % 5])
        ok = ok && consistent(h)
    }
    t.expect(ok, "x100 abrir/cerrar/abrir: estado y movimiento siempre coherentes")
    h.send(.escape); h.advance(1)
    t.expect(h.model.state == .idle && h.motion.progress == 0 && !h.clock.isRunning, "x100 interrumpido: converge a idle, progreso 0, reloj parado")
    h.send(.hotkey); h.advance(1)
    t.expect(h.model.state == .expanded(.home) && h.motion.progress == 1 && !h.clock.isRunning, "x100 interrumpido: luego abre a expandido exacto")
    t.expect(h.maxAnimatesPerStep <= 1, "como mucho una animación geométrica por paso")

    // Paseo aleatorio: todos los eventos y temporizadores, invariantes en cada paso.
    let events: [SurfaceEvent] = [.pointerEnter, .pointerExit, .click, .hotkey, .escape, .dragEntered, .dragExited, .drop,
        .activityChanged(.media(playing: true)), .activityChanged(nil), .activityChanged(.error), .selectModule(.media),
        .selectModule(.shelf), .screenChanged, .fullscreenChanged(true), .fullscreenChanged(false), .permissionChanged,
        .setEnabled(false), .setEnabled(true)] // transitionFinished lo emite el coordinador real, no el azar
    var violations = 0, steps = 0
    for seed in 1...20 {
        let w = Harness()
        var rng = LCG(s: UInt64(seed))
        for _ in 0..<1500 {
            switch rng.next(10) {
            case 0, 1, 2: w.advance(Double(rng.next(40)) / 100)       // 0…0.39 s: dispara temporizadores y fotogramas
            case 3: w.ctx.isInteracting.toggle()
            default: w.send(events[rng.next(events.count)])
            }
            steps += 1
            if !consistent(w) { violations += 1 }
            if w.maxAnimatesPerStep > 1 { violations += 1 }
            if w.motion.progress < 0 || w.motion.progress > 1 { violations += 1 }
        }
        w.ctx.isInteracting = false
        w.send(.setEnabled(true)); w.send(.fullscreenChanged(false)); w.send(.escape); w.advance(3)
        if w.motion.isAnimating || w.clock.isRunning { violations += 1 }
    }
    t.expect(violations == 0, "paseo aleatorio (\(steps) pasos): sin violaciones de invariantes", "\(violations)")
}

// MARK: Tamaños y alas (ADR 0003)

@MainActor private func sizeTokens(_ t: SelfCheck) {
    let s = SurfaceSizes()
    t.expect(s.expanded == CGSize(width: 600, height: 380), "expandido por defecto 600x380")
    // Rejilla de Widgets medida en pantalla real: 2 columnas (>= 2x200 + 8 + 2x(14+16) de margen + 16 de relleno) y ~293 pt de rejilla + ~150 de marco.
    let chrome: CGFloat = 2 * 30 + 16          // márgenes laterales (radio 14 + 16) y relleno de la rejilla
    let twoColumns: CGFloat = 2 * 200 + 8 + chrome, threeColumns: CGFloat = 3 * 200 + 2 * 8 + chrome
    t.expect(s.expanded.width >= twoColumns && s.expanded.width < threeColumns, "ancho: 2 columnas de widgets, no 3")
    t.expect(s.expanded.height >= 150 + 200, "alto: marco (~150 con la zona del notch) + al menos dos filas de widgets (la rejilla se desplaza)")
    // Alas: el texto "mm:ss" del temporizador (caption monoespaciado, 28.75 pt medidos) más 12 pt de relleno exterior.
    t.expect(s.wing >= 12 + 28.75 && s.wing < 48, "alas: caben mm:ss y son más estrechas que las 48 pt originales")
    // Portátil de 13" sin notch (visible 1440x875) y un monitor pequeño: el panel cabe sin recorte salvo el estrictamente necesario.
    let air = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), scale: 2)
    t.expect(NotchGeometry.layout(for: air, requested: .notch)?.expanded.size == s.expanded, "pantalla 1440x900 sin notch: sin recorte")
    let tiny = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1024, height: 600), visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 575), scale: 1)
    let lt = NotchGeometry.layout(for: tiny, requested: .notch)
    t.expect(lt.map { tiny.visibleFrame.contains($0.expanded) && $0.expanded.size == s.expanded } ?? false, "pantalla 1024x600: cabe sin recorte")
    let netbook = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 800, height: 380), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 355), scale: 1)
    t.expect(NotchGeometry.layout(for: netbook, requested: .notch).map { netbook.visibleFrame.contains($0.expanded) && $0.expanded.height < s.expanded.height } ?? false,
             "pantalla 800x480: se recorta dentro del área visible")
}

// MARK: Pantalla completa

private let display = CGRect(x: 0, y: 0, width: 1710, height: 1107)
private func win(_ owner: String, pid: Int32 = 100, layer: Int = 0, _ b: CGRect, name: String? = nil) -> WindowSample {
    WindowSample(owner: owner, pid: pid, layer: layer, bounds: b, name: name)
}

@MainActor final class FakeDetector: FullscreenDetector {
    var initial = false
    var handler: (@MainActor (Bool) -> Void)?
    private(set) var starts = 0, stops = 0
    func start(_ onChange: @escaping @MainActor (Bool) -> Void) { starts += 1; handler = onChange; onChange(initial) }
    func stop() { stops += 1; handler = nil }
    func emit(_ on: Bool) { handler?(on) }
}

@MainActor private func controller(_ detector: FullscreenDetector? = nil, configure: (inout SurfaceConfig) -> Void = { _ in })
    -> (SurfaceWindowController, ManualClock) {
    NSApplication.shared.setActivationPolicy(.accessory) // como la app real
    let clock = ManualClock()
    var cfg = SurfaceConfig()
    cfg.hotKey = nil
    cfg.context.openOnHover = false
    configure(&cfg)
    let c = SurfaceWindowController(config: cfg, motion: MotionCoordinator(clock: clock), fullscreenDetector: detector)
    c.motion.systemReduceMotion = { false }
    return (c, clock)
}

@MainActor private func fullscreenSuite(_ t: SelfCheck) {
    sizeTokens(t)
    // Heurística pura con ventanas sintéticas (datos tomados del spike real en este Mac, ver ADR 0003).
    let backdrop = win("WindowManager", layer: FullscreenHeuristic.backdropLayer, display, name: "Fullscreen Backdrop")
    let wallpaper = win("WindowManager", layer: FullscreenHeuristic.backdropLayer - 2, display, name: "Wallpaper")
    let maximized = win("Brave Browser", CGRect(x: 0, y: 34, width: 1710, height: 1073))
    let menubar = win("Window Server", pid: 597, layer: 24, CGRect(x: 0, y: 0, width: 1710, height: 34))
    let fsApp = win("spike", CGRect(x: 0, y: 34, width: 1710, height: 1073)) // fullscreen nativo en notch: IDÉNTICO al maximizado
    let own = Int32(77)
    func fs(_ w: [WindowSample], d: CGRect = display) -> Bool { FullscreenHeuristic.isFullscreen(windows: w, display: d, ownPID: own) }

    t.expect(FullscreenHeuristic.backdropLayer == -2147483622, "capa del backdrop = desktopWindow + 1 (medida: -2147483622)")
    t.expect(!fs([]), "sin ventanas: no fullscreen")
    t.expect(!fs([menubar, maximized, wallpaper]), "escritorio normal con ventana maximizada: no fullscreen")
    t.expect(!fs([menubar, fsApp]), "LIMITACIÓN: la geometría de la app sola (fullscreen nativo en notch) no distingue de maximizada")
    t.expect(fs([menubar, fsApp, wallpaper, backdrop]), "Space de pantalla completa: backdrop del sistema -> fullscreen")
    t.expect(fs([win("WindowManager", layer: FullscreenHeuristic.backdropLayer, display)]), "backdrop reconocido por capa aunque no haya nombre (sin Screen Recording)")
    t.expect(fs([win("WindowManager", layer: -5, display, name: "Fullscreen Backdrop")]), "backdrop reconocido por nombre si la capa cambiase")
    t.expect(!fs([win("OtraApp", layer: FullscreenHeuristic.backdropLayer, display)]), "misma capa pero otro propietario: no cuenta")
    t.expect(!fs([win("WindowManager", layer: FullscreenHeuristic.backdropLayer, CGRect(x: 1710, y: 0, width: 1710, height: 1107))]),
             "backdrop de OTRA pantalla: no cuenta para la pantalla del panel")
    t.expect(fs([win("WindowManager", layer: FullscreenHeuristic.backdropLayer, CGRect(x: 1710, y: 0, width: 1920, height: 1080))],
                d: CGRect(x: 1710, y: 0, width: 1920, height: 1080)), "backdrop de la pantalla externa donde está el panel: sí")
    t.expect(!fs([win("WindowManager", pid: own, layer: FullscreenHeuristic.backdropLayer, display)]), "ventanas propias se ignoran")
    t.expect(fs([win("Juego", CGRect(x: 0, y: 0, width: 1710, height: 1107))]), "R2: ventana normal de otra app que cubre toda la pantalla (kiosco/juego)")
    t.expect(!fs([win("Juego", pid: own, CGRect(x: 0, y: 0, width: 1710, height: 1107))]), "R2: la propia ventana a toda pantalla no cuenta")
    t.expect(!fs([win("Overlay", layer: 25, CGRect(x: 0, y: 0, width: 1710, height: 1107))]), "R2: capas de overlay (no 0) no cuentan")
    t.expect(fs([win("Juego", CGRect(x: -0.5, y: -0.5, width: 1711, height: 1108))]), "R2: tolerancia de 1 pt")
    t.expect(!fs([win("App", CGRect(x: 0, y: 0, width: 1710, height: 1090))]), "R2: casi toda la pantalla pero sin cubrirla: no cuenta")

    // Controlador con detector falso.
    let fake = FakeDetector()
    let (c, clock) = controller(fake)
    c.start()
    defer { c.stop() }
    guard let L = c.layout else { print("SKIP fullscreen/teclado/hit-region (controlador): sin pantalla con geometría válida"); return }
    t.expect(fake.starts == 1 && c.panelIsVisible && c.model.state == .idle, "detector: start() lo arranca una vez; visible si no hay fullscreen")
    c.send(.click); clock.advance(1)
    fake.emit(true)
    t.expect(c.model.state == .suspended && !c.panelIsVisible && c.model.fullscreenActive, "detector: fullscreen con panel abierto (hide) -> suspendida y oculta")
    fake.emit(false); clock.advance(1)
    t.expect(c.model.state == .idle && c.panelIsVisible && L.idle.width > 0, "detector: salir de fullscreen -> reaparece plegada")

    // Política keepVisible: no se oculta; cambiar la política en caliente reevalúa con el fullscreen activo.
    var cfg = c.config
    cfg.context.fullscreenPolicy = .keepVisible
    c.config = cfg; c.context = cfg.context
    fake.emit(true)
    t.expect(c.model.state == .idle && c.panelIsVisible && c.model.fullscreenActive, "keepVisible: fullscreen no oculta")
    cfg.context.fullscreenPolicy = .hide
    c.config = cfg; c.context = cfg.context
    t.expect(c.model.state == .suspended && !c.panelIsVisible, "política keepVisible -> hide con fullscreen activo: se oculta en el acto")
    cfg.context.fullscreenPolicy = .keepVisible
    c.config = cfg; c.context = cfg.context
    t.expect(c.model.state == .idle && c.panelIsVisible, "política hide -> keepVisible con fullscreen activo: reaparece en el acto")
    fake.emit(false)

    // Arranque con fullscreen ya activo: la superficie nace suspendida (el veredicto llega antes de activar).
    c.stop()
    let early = FakeDetector(); early.initial = true
    let (c2, _) = controller(early)
    c2.start()
    t.expect(c2.model.state == .suspended && !c2.panelIsVisible, "arranque con una app ya a pantalla completa: suspendida y oculta")
    early.emit(false)
    t.expect(c2.model.state == .idle && c2.panelIsVisible, "...y reaparece al salir")
    c2.stop()
    t.expect(early.stops == 1 && early.handler == nil, "stop() detiene el detector")

    // Máquina: habilitar durante fullscreen respeta la política.
    var keep = SurfaceContext(); keep.fullscreenPolicy = .keepVisible
    var m = SurfaceModel(state: .hidden); m.fullscreenActive = true
    t.expect(SurfaceStateMachine.reduce(m, .setEnabled(true), keep).0.state == .idle, "setEnabled durante fullscreen con keepVisible: visible")
    t.expect(SurfaceStateMachine.reduce(m, .setEnabled(true), SurfaceContext()).0.state == .suspended, "setEnabled durante fullscreen con hide: suspendida")
}

// MARK: Teclado y región de clics

@MainActor private func keyEvent(_ code: Int, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                     characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
}

@MainActor private func keyboardAndHitRegionSuite(_ t: SelfCheck) {
    // Máquina: quién abre cuenta como intención explícita.
    func run(_ events: [SurfaceEvent], from m: SurfaceModel = SurfaceModel(), ctx: SurfaceContext = SurfaceContext()) -> SurfaceModel {
        var model = m
        for e in events { model = SurfaceStateMachine.reduce(model, e, ctx).0 }
        return model
    }
    let ctx = SurfaceContext()
    t.expect(run([.click]).openedExplicitly, "clic: apertura explícita")
    t.expect(run([.hotkey]).openedExplicitly, "atajo: apertura explícita")
    var hover = SurfaceModel()
    hover = SurfaceStateMachine.reduce(hover, .pointerEnter, ctx).0
    hover = SurfaceStateMachine.fire(hover, .hoverOpen, ctx).0
    t.expect(hover.isOpening && !hover.openedExplicitly, "hover: apertura NO explícita")
    t.expect(SurfaceStateMachine.reduce(hover, .click, ctx).0.openedExplicitly, "clic dentro de un panel abierto por hover lo hace explícito")
    t.expect(!run([.dragEntered]).openedExplicitly, "arrastre: apertura NO explícita")
    t.expect(!run([.click, .escape]).openedExplicitly && !run([.click, .setEnabled(false)]).openedExplicitly, "cerrar/ocultar borra la intención")
    var instant = SurfaceContext(); instant.hoverDelay = 0
    t.expect(!run([.pointerEnter], ctx: instant).openedExplicitly && run([.pointerEnter], ctx: instant).isOpening, "hover sin retraso: abre sin intención explícita")

    // Compatibilidad del Bool antiguo.
    var cfg = SurfaceConfig()
    t.expect(cfg.keyboardPolicy == .explicitOpenOnly && cfg.takesKeyboardWhenExpanded, "defecto: explicitOpenOnly (Bool antiguo = true)")
    cfg.takesKeyboardWhenExpanded = false
    t.expect(cfg.keyboardPolicy == .never, "Bool antiguo false = never")
    cfg.takesKeyboardWhenExpanded = true
    t.expect(cfg.keyboardPolicy == .explicitOpenOnly, "Bool antiguo true = explicitOpenOnly")

    let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier

    // Hover (sin teclado): el panel no puede ser key, así que no roba el foco de escritura.
    var (c, clock) = controller(nil) { $0.context.openOnHover = true; $0.context.hoverDelay = 0 }
    c.start()
    guard c.layout != nil else { print("SKIP teclado/hit-region: sin pantalla con geometría válida"); c.stop(); return }
    c.send(.pointerEnter); clock.advance(1)
    t.expect(c.model.state == .expanded(.home) && !c.model.openedExplicitly, "hover: abre")
    t.expect(!c.panelIsKey && !NSApp.isActive, "hover: el panel NO toma el teclado ni activa la app (policy explicitOpenOnly)")
    // Clic dentro del panel abierto por hover = intención explícita: pasa a recibir teclado.
    c.send(.click)
    t.expect(c.panelIsKey, "clic dentro del panel abierto por hover: toma el teclado")
    c.stop()

    // Clic: key sin activar la app; Escape cierra y devuelve el foco.
    (c, clock) = controller(nil)
    c.start()
    c.send(.click)
    t.expect(c.panelIsKey, "clic: el panel es key mientras se abre")
    clock.advance(1)
    t.expect(c.panelIsKey && c.model.state == .expanded(.home), "clic: sigue key con el panel expandido")
    t.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore, "clic: la app en primer plano NO cambia (frontmostApplication)")
    c.deliverKeyDown(keyEvent(53)) // Escape por el camino real de AppKit (sendEvent)
    t.expect(c.model.state == .collapsing, "Escape (vía sendEvent del panel) cierra el panel")
    t.expect(!c.panelIsKey && !NSApp.isActive, "al cerrar se devuelve el teclado: ni key ni app activa")
    clock.advance(1)
    t.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore, "tras cerrar: frontmostApplication igual que antes")

    // Escape progresivo: primero el submenú/selección, luego el panel.
    var dismissed = 0
    c.onDismissInteraction = { dismissed += 1 }
    c.send(.hotkey); clock.advance(1)
    t.expect(c.panelIsKey, "atajo: key")
    c.context.isInteracting = true
    t.expect(c.handleKeyDown(keyEvent(53)) && c.model.state == .expanded(.home) && dismissed == 1, "Escape progresivo 1/2: cierra el submenú, el panel sigue")
    c.context.isInteracting = false
    t.expect(c.handleKeyDown(keyEvent(53)) && c.model.state == .collapsing, "Escape progresivo 2/2: cierra el panel")
    clock.advance(1)
    t.expect(!c.handleKeyDown(keyEvent(53)), "panel cerrado: Escape no se consume (pasa a la app)")

    // ← / → entre módulos (sin vuelta; sin modificadores; solo abierto).
    c.modules = [.home, .media, .shelf]
    c.send(.hotkey); clock.advance(1)
    t.expect(c.handleKeyDown(keyEvent(124)) && c.model.state == .expanded(.media), "→ : módulo siguiente")
    c.deliverKeyDown(keyEvent(124))
    t.expect(c.model.state == .expanded(.shelf), "→ vía sendEvent: siguiente")
    t.expect(c.handleKeyDown(keyEvent(124)) && c.model.state == .expanded(.shelf), "→ en el último: no da la vuelta (se consume, sin cambio)")
    t.expect(c.handleKeyDown(keyEvent(123)) && c.model.state == .expanded(.media), "← : módulo anterior")
    t.expect(!c.handleKeyDown(keyEvent(123, .command)) && c.model.state == .expanded(.media), "⌘← no se consume")
    t.expect(!c.handleKeyDown(keyEvent(0)), "otras teclas no se consumen")
    c.modules = [.home, .shelf] // media deshabilitado en Ajustes mientras está seleccionado
    t.expect(c.handleKeyDown(keyEvent(123)) && c.model.state == .expanded(.home), "módulo actual fuera de la lista: salta al primero")
    // ⌘1…⌘6: módulo por posición en el orden activo.
    c.modules = [.home, .media, .shelf]
    t.expect(c.handleKeyDown(keyEvent(19, .command)) && c.model.state == .expanded(.media), "⌘2: segundo módulo activo")
    t.expect(c.handleKeyDown(keyEvent(18, .command)) && c.model.state == .expanded(.home), "⌘1: primer módulo activo")
    t.expect(!c.handleKeyDown(keyEvent(21, .command)) && c.model.state == .expanded(.home), "⌘4 sin cuarto módulo: no se consume")
    t.expect(!c.handleKeyDown(keyEvent(19)) && !c.handleKeyDown(keyEvent(19, [.command, .shift])), "2 sin ⌘ o con ⇧⌘ no se consume")
    c.send(.escape); clock.advance(1)
    t.expect(!c.handleKeyDown(keyEvent(124)), "cerrado: las flechas no se consumen")
    t.expect(!c.handleKeyDown(keyEvent(18, .command)), "cerrado: ⌘1 no se consume")
    c.stop()

    // never / always.
    (c, clock) = controller(nil) { $0.keyboardPolicy = .never }
    c.start(); c.send(.click); clock.advance(1)
    t.expect(!c.panelIsKey, "never: ni con clic toma el teclado")
    c.stop()
    (c, clock) = controller(nil) { $0.keyboardPolicy = .always; $0.context.openOnHover = true; $0.context.hoverDelay = 0 }
    c.start(); c.send(.pointerEnter); clock.advance(1)
    t.expect(c.panelIsKey && !c.model.openedExplicitly, "always: también por hover")
    c.send(.pointerExit)
    c.stop()
    t.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore, "ninguna ruta cambió la app en primer plano")

    // Región de clics: el área transparente de la ventana en transición no captura el ratón.
    (c, clock) = controller(nil)
    c.start()
    if let L = c.layout {
        let outside = CGPoint(x: L.expanded.minX + 3, y: L.expanded.minY + 3)           // esquina inferior izquierda del rect grande
        let inside = CGPoint(x: L.idle.midX, y: L.idle.maxY - 2)                         // sobre el notch
        c.setPointerProvider { outside }
        c.send(.hotkey); clock.advance(0.05)
        t.expect(c.motion.isAnimating && c.panelIgnoresMouse, "transición con el puntero fuera de la forma: la ventana ignora el ratón")
        c.setPointerProvider { inside }
        clock.advance(1.0 / 60)
        t.expect(!c.panelIgnoresMouse, "puntero dentro de la forma: la ventana vuelve a recibirlo (re-evaluado por fotograma)")
        c.setPointerProvider { outside }
        clock.advance(1.0 / 60)
        t.expect(c.panelIgnoresMouse, "puntero fuera otra vez: vuelve a ignorar")
        clock.advance(1)
        t.expect(!c.motion.isAnimating && !c.panelIgnoresMouse, "asentado: la ventana mide lo mismo que la forma y recibe el ratón")
        c.send(.escape); clock.advance(0.05)
        t.expect(c.panelIgnoresMouse, "cierre en curso con el puntero fuera de la forma: ignora")
        clock.advance(1)
        t.expect(!c.panelIgnoresMouse, "cerrado: recibe el ratón en la forma de reposo")
        // La salida de la forma se sintetiza como pointerExit (con ignoresMouseEvents AppKit no la entrega).
        c.send(.hotkey); clock.advance(1); c.send(.escape); clock.advance(1) // en reposo, progreso 0
        c.setPointerProvider { inside }
        c.send(.pointerEnter); c.send(.hotkey); clock.advance(0.02)
        t.expect(c.model.pointerInside, "puntero dentro de la forma: pointerInside se mantiene")
        c.setPointerProvider { outside }
        clock.advance(0.05)
        t.expect(!c.model.pointerInside, "puntero sale de la forma durante la transición: pointerExit sintetizado")
    }
    c.stop()
}

// MARK: Aviso de arrastre (evita Mission Control en el borde superior)

@MainActor private func dragProximitySuite(_ t: SelfCheck) {
    let rest = CGRect(x: 720.5, y: 1073.5, width: 269, height: 33.5) // compacto del notch de 1710 x 1107
    let zone = DragProximity.zone(around: rest)
    t.expect(zone.maxY >= rest.maxY && zone.minY < rest.minY - 70, "aviso de arrastre: la zona cubre el borde superior y baja ~110 pt")
    t.expect(zone.minX == rest.minX - 80 && zone.width == rest.width + 160, "aviso de arrastre: 80 pt extra a cada lado")
    let inside = CGPoint(x: 855, y: 1050)
    t.expect(DragProximity.isFileDragInZone(point: inside, zone: zone, changeCount: 5, baseline: 4, hasFiles: true), "aviso: arrastre de archivos dentro de la zona")
    t.expect(!DragProximity.isFileDragInZone(point: CGPoint(x: 855, y: 700), zone: zone, changeCount: 5, baseline: 4, hasFiles: true), "aviso: fuera de la zona no avisa")
    t.expect(!DragProximity.isFileDragInZone(point: inside, zone: zone, changeCount: 4, baseline: 4, hasFiles: true), "aviso: portapapeles sin cambios = contenido viejo, no avisa (arrastrar una ventana)")
    t.expect(!DragProximity.isFileDragInZone(point: inside, zone: zone, changeCount: 5, baseline: 4, hasFiles: false), "aviso: arrastre que no es de archivos no avisa")
    t.expect(!DragProximity.isFileDragInZone(point: inside, zone: nil, changeCount: 5, baseline: 4, hasFiles: true), "aviso: sin superficie válida no avisa")
}

// MARK: Deslizamiento de dos dedos y título del compacto

@MainActor private func swipeSuite(_ t: SelfCheck) {
    func gesture(_ steps: [(CGFloat, CGFloat)], threshold: CGFloat = 40) -> [SwipeDirection] {
        var d = SwipeDetector(threshold: threshold)
        var out: [SwipeDirection] = []
        for (i, s) in steps.enumerated() {
            if let r = d.feed(dx: s.0, dy: s.1, phase: i == 0 ? .began : .changed) { out.append(r) }
        }
        return out
    }
    t.expect(gesture([(-10, 0), (-15, 1), (-20, 0)]) == [.next], "swipe: dedos a la izquierda cruzan el umbral = siguiente")
    t.expect(gesture([(10, 0), (15, 0), (20, 0)]) == [.previous], "swipe: dedos a la derecha = anterior")
    t.expect(gesture([(-10, 0), (-10, 0), (-10, 0)]).isEmpty, "swipe: por debajo del umbral no dispara")
    t.expect(gesture([(-30, 0), (-30, 0), (-30, 0), (-30, 0)]) == [.next], "swipe: un gesto largo dispara una sola vez (bloqueo)")
    t.expect(gesture([(0, 45), (-25, 0), (-25, 0), (-25, 0)]).isEmpty && gesture([(-20, 25), (-30, 10)]).isEmpty,
             "swipe: movimiento sobre todo vertical no dispara")
    t.expect(gesture([(0, 50), (-60, 0)]).isEmpty, "swipe: gesto vertical descartado no se convierte en horizontal")
    var d = SwipeDetector()
    _ = d.feed(dx: -50, dy: 0, phase: .began)
    t.expect(d.feed(dx: -50, dy: 0, phase: .changed) == nil, "swipe: bloqueado hasta que acaba el gesto")
    _ = d.feed(dx: 0, dy: 0, phase: .ended)
    t.expect(d.feed(dx: -50, dy: 0, phase: .began) == .next, "swipe: gesto nuevo tras terminar el anterior")
    d = SwipeDetector()
    _ = d.feed(dx: -50, dy: 0, phase: .began); _ = d.feed(dx: 0, dy: 0, phase: .ended)
    t.expect(d.feed(dx: -50, dy: 0, phase: .changed) == .next, "swipe: sin .began perdido, el acumulado de otro gesto no pesa")

    // Controlador: solo con la multimedia en el compacto; el ala sin título es la normal (avisos, siempre ancha).
    let (c, clock) = controller(nil)
    c.start()
    guard let layout = c.layout else { print("SKIP swipe/título: sin pantalla con geometría válida"); c.stop(); return }
    func width(is r: CGRect) -> Bool { abs(c.panelFrame.width - r.width) < 1 } // la ventana se alinea a píxeles
    var got: [SwipeDirection] = []
    c.onSwipe = { got.append($0) }
    c.deliverSwipe(.next)
    t.expect(got.isEmpty, "swipe: en reposo sin actividad no avisa")
    c.send(.activityChanged(.media(playing: true))); clock.advance(1)
    c.deliverSwipe(.next); c.deliverSwipe(.previous)
    t.expect(got == [.next, .previous], "swipe: con la multimedia en el compacto avisa")
    t.expect(width(is: layout.compact), "compacto con título: alas simétricas de ancho fijo")
    var cfg = c.config; cfg.showCompactTitle = false; c.config = cfg
    t.expect(width(is: layout.compact), "sin título: el mismo ancho")
    c.send(.activityChanged(.alert))
    t.expect(width(is: layout.compact), "los avisos usan el mismo ancho")
    c.send(.activityChanged(.timer)); c.deliverSwipe(.next)
    t.expect(got.count == 2 && width(is: layout.compact), "temporizador: no hay swipe de canciones y sin título usa el mismo ancho")
    c.send(.activityChanged(.media(playing: true))); c.send(.hotkey); clock.advance(1)
    c.deliverSwipe(.next)
    t.expect(got.count == 2, "swipe: con el panel abierto no avisa (el desplazamiento es del contenido)")
    c.stop()
}
