import AppKit
import AuraCore
import AuraNotchSurface

// Suite QA. Deterministas: reloj manual, sin hardware
// ni temporizadores reales. Los casos "FINDING:" son defectos reproducibles y NO se relajan:
// si fallan, el fallo es el hallazgo.
// IDs: QA-SM-* reducer puro · QA-MC-* coordinador de movimiento · QA-CT-* SurfaceWindowController real.

/// Reloj manual propio (no depende de los tipos internos de SurfaceTests.swift).
@MainActor private final class QAClock: MotionClock {
    var now: TimeInterval = 0
    private var tick: (@MainActor () -> Void)?
    var isRunning: Bool { tick != nil }
    func start(_ tick: @escaping @MainActor () -> Void) { self.tick = tick }
    func stop() { tick = nil }
    /// Avanza `dt` en pasos de 1/60 s, llamando al tick como lo haría una pantalla.
    func advance(_ dt: TimeInterval) {
        var left = dt
        while left > 1e-12 {
            let s = min(1.0 / 60, left); now += s; left -= s; tick?()
        }
    }
}

/// LCG determinista para recorridos pseudoaleatorios reproducibles.
private struct QARandom {
    var s: UInt64
    mutating func next(_ n: Int) -> Int {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Int((s >> 33) % UInt64(n))
    }
}

/// Reducer puro sobre una secuencia de eventos (sin temporizadores).
private func qaReduce(_ events: [SurfaceEvent], from m: SurfaceModel = SurfaceModel(),
                      ctx: SurfaceContext = SurfaceContext()) -> (SurfaceModel, [SurfaceEffect]) {
    var model = m, fx: [SurfaceEffect] = []
    for e in events {
        let r = SurfaceStateMachine.reduce(model, e, ctx)
        model = r.0; fx += r.1
    }
    return (model, fx)
}

private func qaIsAnimate(_ e: SurfaceEffect) -> Bool { if case .animate = e { true } else { false } }

/// AppKit redondea los marcos de ventana a puntos enteros (p. ej. alto 33.5 → 34): comparación con 1 pt de tolerancia.
private func qaNear(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
}

/// Controlador real con reloj manual. Sin atajo global y sin hover por temporizador real
/// (no hace falta bombear el RunLoop salvo donde se indica).
@MainActor private func qaController() -> (SurfaceWindowController, QAClock) {
    let clock = QAClock()
    var cfg = SurfaceConfig()
    cfg.hotKey = nil
    cfg.context.openOnHover = false
    let c = SurfaceWindowController(config: cfg, motion: MotionCoordinator(clock: clock))
    c.motion.systemReduceMotion = { false }
    return (c, clock)
}

/// Ejecuta `body` con un controlador arrancado. Sin geometría válida en el entorno se omite (SKIP, no PASS).
@MainActor private func qaRun(_ id: String, _ body: (SurfaceWindowController, QAClock, SurfaceLayout) -> Void) {
    let (c, clock) = qaController()
    defer { c.stop() }
    c.start()
    guard let layout = c.layout else {
        print("SKIP \(id): sin pantalla con geometría válida en este entorno (no ejecutado)")
        return
    }
    body(c, clock, layout)
}

private func qaStateKey(_ s: SurfaceState) -> String {
    switch s {
    case .hidden: "hidden"
    case .idle: "idle"
    case .compact: "compact"
    case .expanding: "expanding"
    case .expanded: "expanded"
    case .collapsing: "collapsing"
    case .suspended: "suspended"
    }
}

/// Coherencia visual/lógica del controlador real tras cada paso: ventana, progreso y estado.
@MainActor private func qaFrameMatchesState(_ c: SurfaceWindowController, _ L: SurfaceLayout) -> Bool {
    switch c.model.state {
    case .expanding, .collapsing: qaNear(c.panelFrame, L.expanded) && c.motion.isAnimating
    case .expanded: qaNear(c.panelFrame, L.expanded) && c.motion.progress == 1 && !c.motion.isAnimating
    case .idle: qaNear(c.panelFrame, L.idle) && c.motion.progress == 0 && !c.motion.isAnimating
    case .compact: qaNear(c.panelFrame, L.compact) && c.motion.progress == 0 && !c.motion.isAnimating
    case .hidden, .suspended: !c.panelIsVisible && !c.motion.isAnimating
    }
}

// MARK: - Entrada

@MainActor func runQASuite(_ t: SelfCheck) {
    stateMachineQA(t)
    motionQA(t)
    controllerQA(t)
}

// MARK: - Reducer puro (QA-SM)

@MainActor private func stateMachineQA(_ t: SelfCheck) {
    let ctx = SurfaceContext()
    let animOpen = SurfaceEffect.animate(toExpanded: true, .compactToExpanded)
    let expanding = SurfaceModel(state: .expanding(.home))
    let expanded = SurfaceModel(state: .expanded(.home))
    let collapsing = SurfaceModel(state: .collapsing)

    // QA-SM-01: arrastre que entra durante el colapso reorienta a abrir la shelf (sin snap ni ocultar).
    let (m1, f1) = qaReduce([.dragEntered], from: collapsing, ctx: ctx)
    t.expect(m1.state == .expanding(.shelf) && m1.dragActive && f1.contains(animOpen)
             && !f1.contains(.snap(toExpanded: false)) && !f1.contains(.hideWindow),
             "QA-SM-01 dragEntered durante colapso: reorienta a expanding(shelf) [\(m1.state) \(f1)]")

    // QA-SM-02: arrastre durante la apertura cambia el destino sin reiniciar la animación.
    let (m2, f2) = qaReduce([.dragEntered], from: expanding, ctx: ctx)
    t.expect(m2.state == .expanding(.shelf) && !f2.contains(where: qaIsAnimate),
             "QA-SM-02 dragEntered durante apertura: retag a shelf sin nueva animación [\(m2.state) \(f2)]")

    // QA-SM-03: salir el arrastre durante el colapso no programa nada y el colapso termina en idle.
    let (m3, f3) = qaReduce([.dragExited, .transitionFinished], from: collapsing, ctx: ctx)
    t.expect(m3.state == .idle && !m3.dragActive && !f3.contains(.scheduleTimer(.hoverClose, after: ctx.closeGrace)),
             "QA-SM-03 dragExited durante colapso: sin cierre programado, termina en idle [\(m3.state) \(f3)]")

    // QA-SM-04 (FINDING F-01): con un arrastre válido activo, ⌃⌥N no debe cerrar el destino (§4.4: "un drag válido mantiene el destino activo").
    let (m4, f4) = qaReduce([.dragEntered, .hotkey], from: SurfaceModel(), ctx: ctx)
    t.expect(m4.isOpening && m4.dragActive,
             "FINDING: F-01 [Baja] hotkey durante un arrastre válido cierra el destino de la shelf (esperado: sigue abierto; obtenido: \(m4.state), dragActive=\(m4.dragActive), fx=\(f4.count) efectos)")

    // QA-SM-05 (FINDING F-03): pérdida de pantalla con un arrastre válido en curso: el destino debe seguir activo.
    let (m5, f5) = qaReduce([.dragEntered, .screenChanged], from: SurfaceModel(), ctx: ctx)
    t.expect(m5.isOpening && m5.dragActive,
             "FINDING: F-03 [Baja] screenChanged durante un arrastre válido pliega el destino y descarta el arrastre (esperado: sigue abierto con dragActive; obtenido: \(m5.state), dragActive=\(m5.dragActive), fx=\(f5.count) efectos)")

    // QA-SM-06: deshabilitar a mitad de apertura corta la animación, oculta y los eventos tardíos no reabren nada.
    let (m6, f6) = qaReduce([.setEnabled(false)], from: expanding, ctx: ctx)
    t.expect(m6.state == .hidden && f6.contains(.snap(toExpanded: false)) && f6.contains(.hideWindow)
             && f6.contains(.cancelTimer(.hoverClose)), "QA-SM-06a setEnabled(false) a mitad de apertura: corta y oculta [\(m6.state) \(f6)]")
    let (m6b, f6b) = qaReduce([.transitionFinished, .pointerEnter, .click, .hotkey, .escape, .dragEntered, .screenChanged],
                              from: m6, ctx: ctx)
    t.expect(m6b.state == .hidden && f6b.isEmpty, "QA-SM-06b eventos tardíos con superficie deshabilitada: sin efectos [\(m6b.state) \(f6b)]")
    let (m6c, f6c) = qaReduce([.setEnabled(true)], from: m6b, ctx: ctx)
    t.expect(m6c.state == .idle && f6c.contains(.showWindow) && !m6c.pointerInside && !m6c.pinned,
             "QA-SM-06c rehabilitar: reaparece plegada, sin restos de la apertura cortada [\(m6c.state)]")

    // QA-SM-07: deshabilitar durante el colapso con un cierre por hover pendiente: el temporizador no dispara nada.
    let (m7, _) = qaReduce([.pointerExit], from: expanded, ctx: ctx)
    let (m7b, f7b) = qaReduce([.setEnabled(false)], from: m7, ctx: ctx)
    let (m7c, f7c) = SurfaceStateMachine.fire(m7b, .hoverClose, ctx)
    t.expect(m7c.state == .hidden && f7c.isEmpty && f7b.contains(.cancelTimer(.hoverClose)),
             "QA-SM-07 setEnabled(false) con cierre pendiente: el temporizador no produce efectos [\(m7c.state) \(f7c)]")

    // QA-SM-08: fullscreen (política hide) a mitad de apertura suspende; al salir, reaparece plegada.
    let (m8, f8) = qaReduce([.fullscreenChanged(true)], from: expanding, ctx: ctx)
    t.expect(m8.state == .suspended && f8.contains(.snap(toExpanded: false)) && f8.contains(.hideWindow),
             "QA-SM-08a fullscreen a mitad de apertura: suspende y oculta [\(m8.state) \(f8)]")
    let (m8b, _) = qaReduce([.dragEntered, .pointerEnter, .click], from: m8, ctx: ctx)
    t.expect(m8b.state == .suspended, "QA-SM-08b suspendida: arrastre, hover y clic ignorados [\(m8b.state)]")
    let (m8c, f8c) = qaReduce([.fullscreenChanged(false)], from: m8b, ctx: ctx)
    t.expect(m8c.state == .idle && f8c.contains(.showWindow), "QA-SM-08c salir de fullscreen: reaparece plegada [\(m8c.state)]")

    // QA-SM-09: deshabilitar mientras está suspendida no vuelve a mostrar la ventana al salir de fullscreen.
    let (m9, _) = qaReduce([.fullscreenChanged(true), .setEnabled(false), .fullscreenChanged(false)], from: SurfaceModel(), ctx: ctx)
    t.expect(m9.state == .hidden, "QA-SM-09 deshabilitada durante fullscreen: salir de fullscreen no la reactiva [\(m9.state)]")

    // QA-SM-10: ráfagas de hover más cortas que el retardo nunca abren. Incluye un disparo tardío del
    // temporizador tras cada salida (como si no se hubiera cancelado): el guard debe impedir abrir.
    var hm = SurfaceModel(), opened = false
    for _ in 0..<40 {
        hm = SurfaceStateMachine.reduce(hm, .pointerEnter, ctx).0
        hm = SurfaceStateMachine.reduce(hm, .pointerExit, ctx).0
        let (c, fc) = SurfaceStateMachine.fire(hm, .hoverOpen, ctx); hm = c
        if fc.contains(where: qaIsAnimate) { opened = true }
    }
    t.expect(!opened && hm.state == .idle, "QA-SM-10 ráfagas de hover (salida antes del retardo, disparo tardío incluido): nunca abre [\(hm.state)]")

    // QA-SM-11: clic durante el retardo de hover abre al instante y cancela el temporizador pendiente.
    let (m11, f11) = qaReduce([.pointerEnter, .click], from: SurfaceModel(), ctx: ctx)
    t.expect(m11.state == .expanding(.home) && f11.contains(.cancelTimer(.hoverOpen)) && f11.contains(animOpen),
             "QA-SM-11 clic durante el retardo de hover: abre y cancela hoverOpen [\(m11.state)]")

    // QA-SM-12: abierto con atajo (fijado) y un arrastre que entra y sale: no se programa cierre por hover.
    let (m12, f12) = qaReduce([.hotkey, .dragEntered, .dragExited], from: SurfaceModel(), ctx: ctx)
    t.expect(m12.pinned && m12.isOpening && !f12.contains(.scheduleTimer(.hoverClose, after: ctx.closeGrace)),
             "QA-SM-12 fijado por atajo + arrastre que sale: no programa cierre [\(m12.state)]")

    // QA-SM-13: un arrastre sobre el panel abierto en otro módulo cambia a shelf sin animar geometría.
    let (m13, f13) = qaReduce([.selectModule(.media), .dragEntered], from: expanded, ctx: ctx)
    let geometric13 = f13.contains { if case .animate = $0 { true } else if case .snap = $0 { true } else { false } }
    t.expect(m13.state == .expanded(.shelf) && !geometric13,
             "QA-SM-13 arrastre sobre panel expandido: solo cambia de módulo, sin animar geometría [\(m13.state) \(f13)]")

    // QA-SM-14: escape con menú/selección activos solo cierra la interacción, nunca el panel.
    var busy = SurfaceContext(); busy.isInteracting = true
    let (m14, f14) = qaReduce([.escape], from: expanded, ctx: busy)
    t.expect(m14.state == .expanded(.home) && f14 == [.dismissInteraction],
             "QA-SM-14 escape con interacción activa: no cierra el panel [\(m14.state) \(f14)]")
}

// MARK: - Coordinador de movimiento (QA-MC)

@MainActor private func motionQA(_ t: SelfCheck) {
    // QA-MC-01: preferencia .none a mitad de vuelo: salto síncrono a 0, reloj parado, una sola notificación.
    let clock = QAClock()
    let mc = MotionCoordinator(clock: clock)
    mc.systemReduceMotion = { false }
    var finished: [Bool] = []
    mc.onFinished = { finished.append($0) }
    mc.animate(toExpanded: true, .compactToExpanded)
    clock.advance(0.05)
    mc.appPreference = .none
    mc.animate(toExpanded: false, .expandedToCompact)
    t.expect(mc.progress == 0 && !mc.isAnimating && !clock.isRunning && finished == [false],
             "QA-MC-01 Reduce Motion (.none) a mitad de vuelo: salto a 0, reloj parado, notifica una vez [p=\(mc.progress) fin=\(finished)]")

    // QA-MC-02: repetir el mismo destino durante la animación no reinicia el reloj ni duplica la notificación.
    let clock2 = QAClock()
    let mc2 = MotionCoordinator(clock: clock2)
    mc2.systemReduceMotion = { false }
    var fin2: [Bool] = []
    mc2.onFinished = { fin2.append($0) }
    mc2.animate(toExpanded: true, .compactToExpanded)
    clock2.advance(0.1)
    mc2.animate(toExpanded: true, .compactToExpanded)
    clock2.advance(1)
    t.expect(mc2.progress == 1 && !clock2.isRunning && fin2 == [true],
             "QA-MC-02 mismo destino repetido durante el vuelo: una notificación final [p=\(mc2.progress) fin=\(fin2)]")

    // QA-MC-03: tres reorientaciones: solo se notifica la finalización del destino final, progreso siempre en 0…1.
    let clock3 = QAClock()
    let mc3 = MotionCoordinator(clock: clock3)
    mc3.systemReduceMotion = { false }
    var fin3: [Bool] = [], outOfRange = 0
    mc3.onFinished = { fin3.append($0) }
    mc3.onProgress = { if $0 < 0 || $0 > 1 { outOfRange += 1 } }
    mc3.animate(toExpanded: true, .compactToExpanded)
    clock3.advance(0.2)
    mc3.animate(toExpanded: false, .expandedToCompact)
    clock3.advance(0.03)
    mc3.animate(toExpanded: true, .compactToExpanded)
    clock3.advance(1)
    t.expect(fin3 == [true] && outOfRange == 0 && mc3.progress == 1,
             "QA-MC-03 tres reorientaciones: solo la finalización del destino final [fin=\(fin3) fuera=\(outOfRange)]")
}

// MARK: - Controlador real (QA-CT)

@MainActor private func controllerQA(_ t: SelfCheck) {
    // QA-CT-01: arranque: visible, plegada, con el rect de reposo.
    qaRun("QA-CT-01") { c, _, L in
        t.expect(c.panelIsVisible && c.model.state == .idle && qaNear(c.panelFrame, L.idle),
                 "QA-CT-01 arranque: visible en idle con el rect de reposo [\(c.model.state) \(c.panelFrame) esperado \(L.idle)]")
    }

    // QA-CT-02: ciclo completo abrir/cerrar: sin geometría residual al asentarse.
    qaRun("QA-CT-02") { c, clock, L in
        c.send(.click); clock.advance(1)
        t.expect(c.model.state == .expanded(.home) && qaNear(c.panelFrame, L.expanded) && c.motion.progress == 1 && !clock.isRunning,
                 "QA-CT-02 apertura asentada: expandido exacto [\(c.model.state) \(c.panelFrame)]")
        c.send(.escape); clock.advance(1)
        t.expect(c.model.state == .idle && qaNear(c.panelFrame, L.idle) && c.motion.progress == 0 && !clock.isRunning,
                 "QA-CT-02 cierre asentado: rect de reposo, progreso 0, reloj parado [\(c.model.state) \(c.panelFrame)]")
    }

    // QA-CT-03: recorrido pseudoaleatorio de 3000 pasos con interrupciones reales (clic, atajo, escape,
    // habilitar/deshabilitar, fullscreen, tiempo). Ventana, progreso y estado coherentes en cada paso.
    qaRun("QA-CT-03") { c, clock, L in
        var rng = QARandom(s: 42)
        let dts: [TimeInterval] = [0, 0.01, 0.05, 0.1, 0.2, 0.4]
        var bad = 0, firstBad = "", visited: Set<String> = [], reversals = 0, prev = ""
        for step in 0..<3000 {
            switch rng.next(9) {
            case 0, 1: c.send(.click)
            case 2: c.send(.hotkey)
            case 3: c.send(.escape)
            case 4: c.setEnabled(rng.next(3) != 0)
            case 5: c.setFullscreenActive(rng.next(4) == 0)
            case 6: c.send(.selectModule(NotchModule.allCases[rng.next(NotchModule.allCases.count)]))
            default: clock.advance(dts[rng.next(dts.count)])
            }
            if !qaFrameMatchesState(c, L) {
                bad += 1
                if firstBad.isEmpty { firstBad = "paso \(step): \(c.model.state) frame=\(c.panelFrame) p=\(c.motion.progress)" }
            }
            let key = qaStateKey(c.model.state)
            visited.insert(key)
            if prev == "collapsing" && key == "expanding" { reversals += 1 } // interrupción real: reorientar en vuelo
            prev = key
        }
        c.setFullscreenActive(false); c.setEnabled(true); c.send(.escape); clock.advance(2)
        t.expect(bad == 0, "QA-CT-03 recorrido de 3000 pasos: ventana y progreso coherentes con el estado [\(bad) incoherencias; primera: \(firstBad)]")
        print("INFO QA-CT-03 cobertura: estados \(visited.sorted()), reorientaciones en vuelo \(reversals)")
        t.expect(visited.count == 6 && reversals > 20,
                 "QA-CT-03 cobertura del recorrido: estados \(visited.sorted()), reorientaciones en vuelo \(reversals)")
        t.expect(c.model.state == .idle && qaNear(c.panelFrame, L.idle) && !clock.isRunning,
                 "QA-CT-03 tras el recorrido converge a idle con reloj parado [\(c.model.state)]")
    }

    // QA-CT-04: deshabilitar a mitad de apertura y a mitad de cierre con el controlador real.
    qaRun("QA-CT-04") { c, clock, L in
        c.send(.click); clock.advance(0.05)
        c.setEnabled(false)
        t.expect(c.model.state == .hidden && !c.panelIsVisible && c.motion.progress == 0 && !c.motion.isAnimating && !clock.isRunning,
                 "QA-CT-04a deshabilitar a mitad de apertura: oculta, progreso 0, reloj parado [\(c.model.state) p=\(c.motion.progress)]")
        clock.advance(1)
        t.expect(c.model.state == .hidden && !c.panelIsVisible, "QA-CT-04b sin finalización tardía tras deshabilitar")
        c.setEnabled(true)
        t.expect(c.model.state == .idle && c.panelIsVisible && qaNear(c.panelFrame, L.idle),
                 "QA-CT-04c rehabilitar: reaparece plegada [\(c.model.state) \(c.panelFrame)]")
        c.send(.click); clock.advance(1); c.send(.escape); clock.advance(0.05)
        c.setEnabled(false)
        t.expect(c.model.state == .hidden && !c.panelIsVisible && c.motion.progress == 0 && !clock.isRunning,
                 "QA-CT-04d deshabilitar a mitad de cierre: oculta, progreso 0, reloj parado [\(c.model.state)]")
    }

    // QA-CT-05: cambio de pantalla con el panel abierto, por el observador real de NSApplication (cola .main).
    qaRun("QA-CT-05") { c, clock, L in
        c.send(.click); clock.advance(1)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        t.expect(c.model.state == .collapsing, "QA-CT-05a cambio de pantalla con panel abierto: pliega [\(c.model.state)]")
        clock.advance(1)
        t.expect(c.model.state == .idle && qaNear(c.panelFrame, L.idle) && c.panelIsVisible,
                 "QA-CT-05b tras el cambio: asienta en idle sin ventana residual [\(c.model.state) \(c.panelFrame)]")
    }

    // QA-CT-06: fullscreen con el panel abierto (política hide): oculta, resetea progreso y reaparece plegada.
    qaRun("QA-CT-06") { c, clock, L in
        c.send(.click); clock.advance(1)
        c.setFullscreenActive(true)
        t.expect(c.model.state == .suspended && !c.panelIsVisible && c.motion.progress == 0,
                 "QA-CT-06a fullscreen con panel abierto: oculta y resetea progreso [\(c.model.state)]")
        c.setFullscreenActive(false); clock.advance(1)
        t.expect(c.model.state == .idle && c.panelIsVisible && qaNear(c.panelFrame, L.idle),
                 "QA-CT-06b salir de fullscreen: reaparece plegada [\(c.model.state) \(c.panelFrame)]")
    }

    // QA-CT-07: cambio de modo en caliente con el panel abierto: el marco sigue al nuevo layout.
    qaRun("QA-CT-07") { c, clock, _ in
        c.send(.click); clock.advance(1)
        var cfg = c.config
        cfg.mode = .topCenterFloating
        c.config = cfg
        if let l2 = c.layout {
            t.expect(qaNear(c.panelFrame, l2.expanded) && c.model.state == .expanded(.home),
                     "QA-CT-07 cambio de modo con panel abierto: marco al nuevo layout [\(c.panelFrame) esperado \(l2.expanded)]")
        }
    }

    // QA-CT-08: arrastre que entra mientras el panel se pliega: reorienta sin saltar el progreso ni ocultar la ventana.
    qaRun("QA-CT-08") { c, clock, L in
        c.send(.click); clock.advance(1)
        c.send(.escape); clock.advance(0.05)
        let before = c.motion.progress
        c.send(.dragEntered)
        t.expect(c.model.state == .expanding(.shelf) && c.motion.isAnimating && c.motion.progress == before && c.panelIsVisible
                 && qaNear(c.panelFrame, L.expanded),
                 "QA-CT-08 dragEntered durante colapso (controlador): reorienta sin salto de progreso [\(c.model.state) p=\(before)->\(c.motion.progress)]")
        clock.advance(1)
        t.expect(c.model.state == .expanded(.shelf) && c.motion.progress == 1 && qaNear(c.panelFrame, L.expanded) && !clock.isRunning,
                 "QA-CT-08b tras soltar la animación: shelf abierta, marco expandido exacto [\(c.model.state)]")
    }

    // QA-CT-09 (FINDING F-02): stop() seguido de start() debe volver a mostrar la superficie.
    qaRun("QA-CT-09") { c, _, _ in
        c.stop()
        c.start()
        t.expect(c.panelIsVisible,
                 "FINDING: F-02 [Baja, latente] stop() + start() deja la superficie invisible (esperado: visible; obtenido: visible=\(c.panelIsVisible), estado=\(c.model.state))")
    }
}
