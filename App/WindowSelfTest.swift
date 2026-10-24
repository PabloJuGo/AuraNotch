import AppKit
import AuraCore
import AuraNotchSurface

/// Verificación real en esta máquina (`AuraNotch --selftest-window`): ventana real, pantalla real,
/// reloj de pantalla real. Imprime PASS/FAIL por comprobación y devuelve el veredicto global.
@MainActor final class WindowSelfTest {
    private let c: SurfaceWindowController
    private var failures = 0
    private var frames = 0
    private var lastProgress = 0.0
    private var maxStep = 0.0, outOfRange = 0

    init(_ controller: SurfaceWindowController) { c = controller }

    private func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — \(detail())")")
        if !ok { failures += 1 }
    }

    private func near(_ a: CGRect, _ b: CGRect, tol: CGFloat = 0.51) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        return cond()
    }

    func run() async -> Bool {
        guard let layout = c.layout, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else {
            check(false, "layout disponible"); return false
        }
        print("pantalla: frame \(screen.frame) modo \(layout.mode) idle \(layout.idle) compact \(layout.compact) expanded \(layout.expanded)")
        check(c.model.state == .idle && c.panelIsVisible, "arranca en idle y visible", "\(c.model.state)")
        check(near(c.panelFrame, layout.idle), "frame en reposo = layout.idle", "\(c.panelFrame)")

        // Observa el progreso por fotograma (reloj real de pantalla).
        let previous = c.motion.onProgress
        c.motion.onProgress = { [self] p in
            previous?(p); frames += 1
            maxStep = max(maxStep, abs(p - lastProgress)); lastProgress = p
            if p < 0 || p > 1 { outOfRange += 1 }
        }

        // 100 ciclos abrir→cerrar interrumpidos a distintos puntos de la transición.
        let delays = [0, 5, 12, 30, 60, 110, 200].map { Duration.milliseconds($0) }
        var maxJump = 0.0
        for i in 0..<100 {
            for step in 0..<2 { // hotkey alterna: abre, y luego cierra a mitad de camino
                let before = c.motion.progress
                c.send(.hotkey)
                maxJump = max(maxJump, abs(c.motion.progress - before)) // reorientar no salta
                try? await Task.sleep(for: delays[(i * 3 + step) % delays.count])
            }
        }
        // El progreso se sincroniza a "ahora" al reorientar: puede avanzar lo que dura un fotograma, nunca más.
        check(maxJump <= maxStep * 1.5 + 0.01, "reorientar no salta más de ~1 fotograma (100 ciclos)", "salto \(maxJump) vs paso \(maxStep)")
        check(outOfRange == 0, "progreso siempre en 0…1 (sin overshoot)", "\(outOfRange) fuera de rango")
        check(frames > 100, "el reloj de pantalla entregó fotogramas", "\(frames)")
        print("info: \(frames) fotogramas, mayor paso entre fotogramas \(String(format: "%.3f", maxStep))")

        // Estado final coherente tras el trasiego.
        if c.model.isOpeningForTest { c.send(.hotkey) }
        let settledIdle = await waitUntil { c.model.state == .idle && !c.motion.isAnimating }
        check(settledIdle, "converge a idle", "\(c.model.state)")
        check(near(c.panelFrame, layout.idle) && c.motion.progress == 0, "geometría final plegada correcta", "\(c.panelFrame) p=\(c.motion.progress)")

        c.send(.hotkey)
        let opened = await waitUntil { c.model.state == .expanded(.home) }
        check(opened, "abre hasta expanded", "\(c.model.state)")
        check(near(c.panelFrame, layout.expanded) && c.motion.progress == 1, "geometría expandida correcta", "\(c.panelFrame)")
        check(screen.frame.insetBy(dx: -0.01, dy: -0.01).contains(c.panelFrame), "el panel no sale de la pantalla", "\(c.panelFrame)")
        if layout.mode == .notch { check(abs(c.panelFrame.maxY - screen.frame.maxY) < 0.01, "anclado al borde superior físico") }
        check(abs(c.panelFrame.midX - layout.idle.midX) < 1 || c.panelFrame.minX == screen.frame.minX || c.panelFrame.maxX == screen.frame.maxX,
              "centrado respecto al notch (o recortado a la pantalla)")

        c.send(.hotkey)
        check(await waitUntil { c.model.state == .idle }, "cierra de vuelta a idle")
        check(near(c.panelFrame, layout.idle), "frame final = layout.idle tras cerrar", "\(c.panelFrame)")

        // Reduce Motion de la app: instantáneo, mismo estado final.
        c.motion.appPreference = .none
        c.send(.hotkey)
        check(c.model.state == .expanded(.home) && c.motion.progress == 1 && near(c.panelFrame, layout.expanded), "Reduce Motion (none): apertura instantánea", "\(c.model.state)")
        c.send(.hotkey)
        check(c.model.state == .idle && c.motion.progress == 0 && near(c.panelFrame, layout.idle), "Reduce Motion (none): cierre instantáneo")
        c.motion.appPreference = .full

        // Deshabilitar/habilitar.
        c.setEnabled(false)
        check(!c.panelIsVisible && c.model.state == .hidden, "deshabilitada: ventana oculta")
        c.setEnabled(true)
        check(c.panelIsVisible && c.model.state == .idle, "rehabilitada: ventana visible")

        c.stop()
        check(NSApp.windows.allSatisfy { !$0.isVisible }, "stop() no deja ventanas visibles huérfanas", "\(NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible)" })")
        print(failures == 0 ? "RESULT PASS" : "RESULT FAIL (\(failures))")
        return failures == 0
    }
}

private extension SurfaceModel {
    var isOpeningForTest: Bool { if case .expanding = state { true } else if case .expanded = state { true } else { false } }
}
