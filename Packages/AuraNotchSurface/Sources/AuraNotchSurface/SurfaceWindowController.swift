import AppKit
import Carbon.HIToolbox
import SwiftUI
import AuraCore

/// Cuándo el panel expandido toma el teclado (key sin activar la app). Ver ADR 0003.
public enum KeyboardPolicy: String, Equatable, Sendable, CaseIterable {
    /// Nunca: Escape y ←/→ no llegan (el foco de escritura de la app en primer plano no se toca jamás).
    case never
    /// Solo si se abrió por clic o atajo (o se hizo clic dentro): nunca por hover ni arrastre.
    case explicitOpenOnly
    /// Siempre que esté expandido, también por hover.
    case always
}

public struct SurfaceConfig {
    public var mode: SurfaceMode = .notch
    public var sizes = SurfaceSizes()
    public var context = SurfaceContext()
    public var keyboardPolicy: KeyboardPolicy = .explicitOpenOnly
    /// Compatibilidad con la API anterior (Bool): `true` = `.explicitOpenOnly`, `false` = `.never`.
    public var takesKeyboardWhenExpanded: Bool {
        get { keyboardPolicy != .never }
        set { keyboardPolicy = newValue ? .explicitOpenOnly : .never }
    }
    /// Atajo global (tecla virtual + modificadores Carbon). Por defecto ⌃⌥N; `nil` = sin atajo.
    public var hotKey: (keyCode: Int, modifiers: Int)? = (kVK_ANSI_N, controlKey | optionKey)
    /// Con `false`, el compacto no lleva texto (canción/temporizador) y usa el ala normal; los avisos siempre lo llevan.
    public var showCompactTitle = true
    public init() {}
}

extension ScreenMetrics {
    @MainActor public init(screen s: NSScreen) {
        self.init(frame: s.frame, visibleFrame: s.visibleFrame, safeAreaTop: s.safeAreaInsets.top,
                  auxTopLeft: s.auxiliaryTopLeftArea, auxTopRight: s.auxiliaryTopRightArea, scale: s.backingScaleFactor)
    }
}

/// Dueño de la ventana: une pantalla, máquina de estados, movimiento y SwiftUI (§6.4).
@MainActor public final class SurfaceWindowController {
    public private(set) var model = SurfaceModel(state: .hidden)
    public var context: SurfaceContext {
        didSet {
            // Cambiar la política con una app a pantalla completa activa debe ocultar/mostrar en el acto.
            if oldValue.fullscreenPolicy != context.fullscreenPolicy, model.fullscreenActive { send(.fullscreenChanged(true)) }
        }
    }
    /// Módulos navegables con ←/→ (los habilitados en Ajustes, en orden).
    public var modules: [NotchModule] = NotchModule.allCases
    public private(set) var layout: SurfaceLayout?
    public let motion: MotionCoordinator
    public let viewModel = SurfaceViewModel()
    public var config: SurfaceConfig { didSet { refreshLayout(); syncWindow() } }

    /// Archivos soltados sobre el panel (la shelf real los consumirá).
    public var onDrop: (([URL]) -> Void)?
    /// Deslizamiento de dos dedos sobre el notch cerrado con la multimedia visible.
    public var onSwipe: ((SwipeDirection) -> Void)?
    /// Escape con menú/selección activos: quien los gestione debe cerrarlos.
    public var onDismissInteraction: (() -> Void)?

    /// Ventana, para inspección en pruebas.
    public var panelFrame: CGRect { panel.frame }
    public var panelIsVisible: Bool { panel.isVisible }
    public var panelIsKey: Bool { panel.isKeyWindow }
    public var panelIgnoresMouse: Bool { panel.ignoresMouseEvents }
    /// Posición del puntero en coordenadas globales AppKit; inyectable en pruebas.
    var pointerProvider: () -> CGPoint = { NSEvent.mouseLocation }
    public func setPointerProvider(_ p: @escaping () -> CGPoint) { pointerProvider = p }

    private let panel = SurfacePanel()
    private let contentView = SurfaceContentView(frame: .zero)
    private var timers: [SurfaceTimer: Timer] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var hotKey: GlobalHotKey?
    private let fullscreenDetector: FullscreenDetector?
    private var clickMonitor: Any?
    private var dragProximity: DragProximityMonitor?
    private var userEnabled = true
    private var started = false
    private var queue: [Input] = []
    private var draining = false
    private enum Input { case event(SurfaceEvent), timer(SurfaceTimer) }

    public init(config: SurfaceConfig = SurfaceConfig(), motion: MotionCoordinator? = nil,
                content: SurfaceContentFactory? = nil, fullscreenDetector: FullscreenDetector? = nil) {
        self.fullscreenDetector = fullscreenDetector
        self.config = config
        self.context = config.context
        self.motion = motion ?? MotionCoordinator(clock: DisplayLinkClock())
        let factory = content ?? { AnyView(SurfacePlaceholderView(model: $0)) }

        let host = NSHostingView(rootView: factory(viewModel))
        host.sizingOptions = [] // el tamaño lo manda el controlador, no el contenido
        host.frame = contentView.bounds
        host.autoresizingMask = [.width, .height]
        contentView.addSubview(host)
        panel.contentView = contentView

        contentView.onEnter = { [unowned self] in send(.pointerEnter) }
        contentView.onExit = { [unowned self] in send(.pointerExit) }
        contentView.onClick = { [unowned self] in send(.click) }
        contentView.onDragEnter = { [unowned self] in send(.dragEntered) }
        contentView.onDragExit = { [unowned self] in
            // Con el cursor aún sobre el panel, el destino pasó a una vista de SwiftUI (p. ej. el `dropDestination` de la shelf):
            // no es una salida real (medido: cerraba el panel a mitad del arrastre). El fin lo da el soltado o `DragProximityMonitor`.
            if model.isOpening, panel.frame.contains(pointerProvider()) { return }
            send(.dragExited)
        }
        contentView.onSwipe = { [unowned self] in deliverSwipe($0) }
        contentView.onDrop = { [unowned self] urls in send(.drop); dragProximity?.syncBaseline(); onDrop?(urls) }
        panel.onKeyDown = { [unowned self] in handleKeyDown($0) }

        self.motion.onProgress = { [unowned self] p in viewModel.progress = p; updateHitRegion() }
        self.motion.onFinished = { [unowned self] _ in send(.transitionFinished) }
    }

    // MARK: - Ciclo de vida

    public func start() {
        started = true
        installObservers()
        if let hk = config.hotKey {
            hotKey = GlobalHotKey(keyCode: hk.keyCode, modifiers: hk.modifiers) { [weak self] in self?.send(.hotkey) }
        }
        // Antes de activar: si ya hay una app a pantalla completa, la superficie arranca suspendida.
        fullscreenDetector?.start { [weak self] on in self?.setFullscreenActive(on) }
        // Un clic dentro del panel (abierto por hover) es intención explícita: pasa a recibir teclado.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            if let self, e.window === self.panel, self.model.isOpening { self.send(.click) }
            return e
        }
        let drag = DragProximityMonitor(
            zone: { [weak self] in self.flatMap { c in c.layout.map { DragProximity.zone(around: c.restFrame(in: $0)) } } },
            onApproach: { [weak self] in
                guard let self, !model.isInactive, model.isRest || model.state == .collapsing else { return }
                send(.dragEntered)
            },
            onEnd: { [weak self] in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    // Si la vista del panel recibió el archivo, `.drop` ya limpió el arrastre. Si el destino pasó a una vista de
                    // SwiftUI o el panel se expandió con el arrastre en marcha, el soltado no llega aquí: se usan los archivos
                    // guardados al detectar el arrastre (la shelf deduplica, así que un doble alta es inocuo).
                    guard let self, model.dragActive else { return }
                    let urls = dragProximity?.capturedURLs ?? []
                    if panel.frame.contains(pointerProvider()), !urls.isEmpty { send(.drop); onDrop?(urls) }
                    else { send(.dragExited) }
                }
            })
        dragProximity = drag
        drag.start()
        refreshLayout() // activa la superficie si hay pantalla válida
    }

    /// Libera observadores, atajo, temporizadores y la ventana (sin ventanas huérfanas).
    public func stop() {
        started = false
        send(.setEnabled(false)) // el modelo queda `hidden`: un start() posterior vuelve a mostrar la ventana
        hotKey?.unregister(); hotKey = nil
        fullscreenDetector?.stop()
        dragProximity?.stop(); dragProximity = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        for (c, o) in observers { c.removeObserver(o) }
        observers = []
        timers.values.forEach { $0.invalidate() }; timers = [:]
        motion.snap(toExpanded: false)
        panel.orderOut(nil)
        panel.close()
    }

    public func setEnabled(_ on: Bool) { userEnabled = on; refreshLayout() }
    /// Lo alimenta el `FullscreenDetector` inyectado; también se puede llamar a mano (pruebas, otros detectores).
    public func setFullscreenActive(_ on: Bool) { send(.fullscreenChanged(on)) }

    // MARK: - Despacho

    public func send(_ event: SurfaceEvent) { enqueue(.event(event)) }

    /// Cola con drenado: un efecto (p. ej. snap con `onFinished`) puede generar eventos
    /// sin reentrar en la máquina a mitad de un paso.
    private func enqueue(_ input: Input) {
        queue.append(input)
        guard !draining else { return }
        draining = true
        while !queue.isEmpty {
            let next = queue.removeFirst()
            let (m, fx): (SurfaceModel, [SurfaceEffect])
            switch next {
            case .event(let e): (m, fx) = SurfaceStateMachine.reduce(model, e, context)
            case .timer(let t): (m, fx) = SurfaceStateMachine.fire(model, t, context)
            }
            model = m
            fx.forEach(perform)
        }
        draining = false
        syncWindow()
    }

    private func perform(_ fx: SurfaceEffect) {
        switch fx {
        case .animate(let expanded, let t): motion.animate(toExpanded: expanded, t)
        case .snap(let expanded): motion.snap(toExpanded: expanded)
        case .scheduleTimer(let t, let after):
            timers[t]?.invalidate()
            let timer = Timer(timeInterval: after, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.timers[t] = nil; self?.enqueue(.timer(t)) }
            }
            RunLoop.main.add(timer, forMode: .common) // también durante menús/arrastres
            timers[t] = timer
        case .cancelTimer(let t): timers.removeValue(forKey: t)?.invalidate()
        case .showWindow: panel.orderFrontRegardless()
        case .hideWindow: panel.orderOut(nil)
        case .updateGeometry: refreshLayout()
        case .dismissInteraction: onDismissInteraction?()
        }
    }

    // MARK: - Geometría y ventana

    /// Pantalla objetivo: la del notch si existe; si no, la principal (la de la barra de menús).
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func refreshLayout() {
        layout = Self.targetScreen().flatMap {
            NotchGeometry.layout(for: ScreenMetrics(screen: $0), requested: config.mode, sizes: config.sizes)
        }
        // Sin superficie válida (p. ej. "no en externa") se desactiva; si vuelve una pantalla válida, se reactiva.
        let want = started && userEnabled && layout != nil
        if want != (model.state != .hidden) { send(.setEnabled(want)) }
    }

    /// Silueta en reposo: sin actividad, el hueco del notch; con actividad, el hueco con alas simétricas de ancho fijo.
    private func restFrame(in layout: SurfaceLayout) -> CGRect {
        model.activity == nil ? layout.idle : layout.compact
    }

    private func syncWindow() {
        viewModel.state = model.state
        viewModel.motion = motion.preference
        guard let layout, !model.isInactive else { panel.ignoresMouseEvents = true; syncKeyboard(); return }
        let rest = restFrame(in: layout)
        let big = model.isOpening || model.state == .collapsing
        let frame = big ? layout.expanded : rest
        viewModel.restFrame = rest; viewModel.expandedFrame = layout.expanded; viewModel.windowFrame = frame
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        updateHitRegion()
        contentView.interceptsClicks = !(model.isOpening && motion.progress >= 1) // expandido: clics al contenido
        syncKeyboard()
    }

    /// Teclado: key (sin activar la app, el panel es nonactivating) solo mientras está abierto y la política lo permite;
    /// al cerrar se devuelve (medido: la ventana de la app en primer plano vuelve a ser key al instante).
    private func syncKeyboard() {
        let wants: Bool
        switch config.keyboardPolicy {
        case .never: wants = false
        case .explicitOpenOnly: wants = model.isOpening && model.openedExplicitly
        case .always: wants = model.isOpening
        }
        panel.allowsKey = wants
        if wants { if !panel.isKeyWindow { panel.makeKey() } }
        else if panel.isKeyWindow { panel.resignKey() }
    }

    /// Durante la transición la ventana mide el rect expandido pero la forma visible es menor: el área transparente
    /// no debe capturar clics. Se re-evalúa en cada fotograma (ya hay reloj) con la posición del puntero.
    /// La salida de la forma se sintetiza como `pointerExit` porque con `ignoresMouseEvents` AppKit no la entrega.
    private func updateHitRegion() {
        guard !model.isInactive, layout != nil else { return }
        guard motion.isAnimating else { panel.ignoresMouseEvents = false; return }
        let inside = Self.shapeRect(rest: viewModel.restFrame, expanded: viewModel.expandedFrame,
                                    progress: motion.progress, preference: motion.preference).contains(pointerProvider())
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
            if !inside, model.pointerInside, !model.dragActive { send(.pointerExit) }
        }
    }

    /// Forma visible en coordenadas globales (mismo criterio que `SurfaceViewModel.shapeRect`).
    static func shapeRect(rest: CGRect, expanded: CGRect, progress: Double, preference: MotionPreference) -> CGRect {
        let p = preference == .full ? progress : (progress >= 0.5 ? 1 : 0)
        return NotchGeometry.lerp(rest, expanded, p)
    }

    /// Solo cuenta con el compacto de multimedia (abierto, el desplazamiento es del contenido). También para pruebas.
    public func deliverSwipe(_ d: SwipeDirection) {
        if case .compact(.media) = model.state { onSwipe?(d) }
    }

    // MARK: - Teclado

    /// Teclas físicas 1…6 (⌘N elige el N-ésimo módulo activo; no depende de la distribución de teclado).
    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]

    /// Escape (progresivo: submenú → panel), ←/→ (módulo anterior/siguiente) y ⌘1…⌘6 (módulo por posición). `true` = consumida.
    /// Solo con el panel abierto; con un campo de texto en edición el panel ni la ofrece (ver `SurfacePanel.sendEvent`).
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        guard model.isOpening else { return false }
        if event.keyCode == UInt16(kVK_Escape) { send(.escape); return true }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == .command {
            guard let i = Self.digitKeys.firstIndex(of: Int(event.keyCode)), modules.indices.contains(i) else { return false }
            send(.selectModule(modules[i])); return true
        }
        guard mods.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: selectAdjacentModule(-1); return true
        case kVK_RightArrow: selectAdjacentModule(1); return true
        default: return false
        }
    }

    /// Entrega una tecla al panel por el mismo camino que AppKit (`sendEvent`); para pruebas.
    public func deliverKeyDown(_ event: NSEvent) { panel.sendEvent(event) }

    /// Sin vuelta (igual que `ModuleNavBar`): en los extremos no hace nada.
    public func selectAdjacentModule(_ delta: Int) {
        guard let i = modules.firstIndex(of: model.module) else { if let f = modules.first { send(.selectModule(f)) }; return }
        let j = i + delta
        if modules.indices.contains(j) { send(.selectModule(modules[j])) }
    }

    // MARK: - Observadores del sistema

    private func installObservers() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (SurfaceWindowController) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
            }
            observers.append((center, token))
        }
        // §4.4 / §3.6: no cerrar mientras haya un menú abierto (selector de fuente, menús contextuales…).
        // Durante el seguimiento de un menú no llegan eventos de ratón: al terminar se resincroniza el puntero.
        observe(.default, NSMenu.didBeginTrackingNotification) { $0.context.isInteracting = true }
        observe(.default, NSMenu.didEndTrackingNotification) { c in
            c.context.isInteracting = false
            if NSEvent.mouseLocation.x >= c.panel.frame.minX, NSEvent.mouseLocation.x <= c.panel.frame.maxX,
               NSEvent.mouseLocation.y >= c.panel.frame.minY, NSEvent.mouseLocation.y <= c.panel.frame.maxY {
                c.send(.pointerEnter)
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.screenParametersChanged() }
        // Tras suspender, el WindowServer puede haber reordenado pantallas/ventanas.
        observe(ws, NSWorkspace.didWakeNotification) { $0.screenParametersChanged() }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.screenParametersChanged() }
        // Sleep: sin acción; el reloj usa tiempo absoluto, así que una animación en curso converge al despertar.
    }

    private func screenParametersChanged() {
        refreshLayout()
        send(.screenChanged)
        if !model.isInactive { panel.orderFrontRegardless() }
    }
}

