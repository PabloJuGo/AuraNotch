import Foundation
import AuraCore

/// Temporizadores que la máquina pide al exterior (sin `sleep`: la máquina es pura).
public enum SurfaceTimer: Equatable, Sendable { case hoverOpen, hoverClose }

/// Efectos que la máquina ordena; los ejecuta `SurfaceWindowController`.
public enum SurfaceEffect: Equatable, Sendable {
    /// Reorienta/inicia la animación hacia expandido (true) o compacto (false).
    case animate(toExpanded: Bool, AuraCore.Transition)
    /// Salto instantáneo (sin animación) y cancelación de la animación en curso.
    case snap(toExpanded: Bool)
    case scheduleTimer(SurfaceTimer, after: TimeInterval)
    case cancelTimer(SurfaceTimer)
    case showWindow, hideWindow
    /// Recalcular el layout desde la pantalla actual (el frame de la ventana se sincroniza siempre tras cada paso).
    case updateGeometry
    /// Escape con menú/selección activos: la UI los cierra antes de cerrar el panel.
    case dismissInteraction
}

public enum FullscreenPolicy: Equatable, Sendable { case hide, keepVisible }

/// Hechos de entorno y configuración que el controlador aporta en cada paso.
public struct SurfaceContext: Equatable, Sendable {
    public var openOnHover = true
    public var openOnClick = true
    public var hoverDelay: TimeInterval = 0.12
    /// Gracia antes de cerrar al salir el puntero (evita parpadeo al cruzar bordes).
    public var closeGrace: TimeInterval = 0.30
    /// Menú contextual abierto, arrastre interno o selección de texto: no cerrar.
    public var isInteracting = false
    public var fullscreenPolicy: FullscreenPolicy = .hide
    public init() {}
}

/// Estado lógico + memoria mínima que `SurfaceState` no puede expresar.
public struct SurfaceModel: Equatable, Sendable {
    public var state: SurfaceState = .idle
    public var activity: ActivityKind?
    public var module: NotchModule = .home
    public var pointerInside = false
    public var dragActive = false
    /// Abierto por atajo: no se cierra al salir el puntero.
    public var pinned = false
    /// Abierto por clic o atajo (intención explícita), no por hover ni arrastre: decide si el panel toma teclado.
    public var openedExplicitly = false
    public var fullscreenActive = false
    public init(state: SurfaceState = .idle) { self.state = state }

    var rest: SurfaceState { activity.map(SurfaceState.compact) ?? .idle }
    public var isRest: Bool { if case .idle = state { true } else if case .compact = state { true } else { false } }
    public var isOpening: Bool { if case .expanding = state { true } else if case .expanded = state { true } else { false } }
    public var isInactive: Bool { state == .hidden || state == .suspended }
}

/// Reducer puro `(modelo, evento, contexto) -> (modelo, efectos)` (§4.4).
public enum SurfaceStateMachine {
    public static func reduce(_ model: SurfaceModel, _ event: SurfaceEvent, _ ctx: SurfaceContext)
        -> (SurfaceModel, [SurfaceEffect]) {
        var m = model, fx: [SurfaceEffect] = []

        if m.isInactive {
            reduceInactive(&m, event, ctx, &fx)
            return (m, fx)
        }

        switch event {
        case .setEnabled(let on):
            if !on { deactivate(&m, to: .hidden, &fx) }
        case .fullscreenChanged(let on):
            m.fullscreenActive = on
            if on && ctx.fullscreenPolicy == .hide { deactivate(&m, to: .suspended, &fx) }
        case .screenChanged:
            // La geometría cambia bajo el panel: se recalcula y se pliega para no dejarlo mal colocado.
            // Excepción (§4.4): un arrastre válido en curso mantiene el destino; el host reubica la ventana.
            fx.append(.updateGeometry)
            if !m.dragActive {
                m.pointerInside = false
                if m.isOpening { close(&m, &fx) }
            }
        case .permissionChanged:
            break
        case .activityChanged(let a):
            m.activity = a
            if m.isRest { m.state = m.rest } // nunca abre ni cierra nada
        case .selectModule(let mod):
            m.module = mod
            if case .expanding = m.state { m.state = .expanding(mod) }
            if case .expanded = m.state { m.state = .expanded(mod) }
        case .pointerEnter:
            m.pointerInside = true
            fx.append(.cancelTimer(.hoverClose))
            if m.state == .collapsing, ctx.openOnHover {
                open(&m, pinned: false, explicit: false, &fx) // el puntero volvió: reorienta sin retraso
            } else if m.isRest, ctx.openOnHover {
                if ctx.hoverDelay <= 0 { open(&m, pinned: false, explicit: false, &fx) }
                else { fx.append(.scheduleTimer(.hoverOpen, after: ctx.hoverDelay)) }
            }
        case .pointerExit:
            m.pointerInside = false
            fx.append(.cancelTimer(.hoverOpen))
            if m.isOpening, !m.dragActive, !m.pinned { fx.append(.scheduleTimer(.hoverClose, after: ctx.closeGrace)) }
        case .click:
            if (m.isRest || m.state == .collapsing), ctx.openOnClick { open(&m, pinned: false, explicit: true, &fx) }
            else if m.isOpening { m.openedExplicitly = true } // clic dentro de un panel abierto por hover: intención explícita
        case .hotkey:
            if m.isOpening { if !m.dragActive { close(&m, &fx) } } // un arrastre válido mantiene el destino (§4.4)
            else { open(&m, pinned: true, explicit: true, &fx) }
        case .escape:
            if ctx.isInteracting { fx.append(.dismissInteraction) }
            else if m.isOpening { close(&m, &fx) }
        case .dragEntered:
            m.dragActive = true; m.pointerInside = true
            fx += [.cancelTimer(.hoverOpen), .cancelTimer(.hoverClose)]
            m.module = .shelf // el destino del arrastre es la shelf
            if m.isRest || m.state == .collapsing { open(&m, pinned: false, explicit: false, &fx) }
            else if m.isOpening { m.state = retag(m.state, .shelf) }
        case .dragExited:
            m.dragActive = false; m.pointerInside = false
            if m.isOpening, !m.pinned { fx.append(.scheduleTimer(.hoverClose, after: ctx.closeGrace)) }
        case .drop:
            m.dragActive = false; m.pointerInside = true
            fx.append(.cancelTimer(.hoverClose))
        case .transitionFinished:
            switch m.state {
            case .expanding(let mod): m.state = .expanded(mod)
            case .collapsing: m.state = m.rest
            default: break // finalización tardía/obsoleta: se ignora
            }
        }
        return (m, fx)
    }

    /// Dispara un temporizador previamente pedido con `scheduleTimer`.
    public static func fire(_ model: SurfaceModel, _ timer: SurfaceTimer, _ ctx: SurfaceContext)
        -> (SurfaceModel, [SurfaceEffect]) {
        var m = model, fx: [SurfaceEffect] = []
        guard !m.isInactive else { return (m, fx) }
        switch timer {
        case .hoverOpen:
            if m.isRest, m.pointerInside, ctx.openOnHover { open(&m, pinned: false, explicit: false, &fx) }
        case .hoverClose:
            guard m.isOpening, !m.dragActive, !m.pinned, !m.pointerInside else { break }
            if ctx.isInteracting { fx.append(.scheduleTimer(.hoverClose, after: ctx.closeGrace)) }
            else { close(&m, &fx) }
        }
        return (m, fx)
    }

    // MARK: - Helpers

    private static func reduceInactive(_ m: inout SurfaceModel, _ event: SurfaceEvent, _ ctx: SurfaceContext, _ fx: inout [SurfaceEffect]) {
        switch event {
        case .activityChanged(let a): m.activity = a
        case .selectModule(let mod): m.module = mod
        case .fullscreenChanged(let on):
            m.fullscreenActive = on
            // También reaparece si la política pasa a keepVisible mientras estaba suspendida (ver `policyChanged`).
            if m.state == .suspended, !on || ctx.fullscreenPolicy == .keepVisible { activate(&m, &fx) }
        case .setEnabled(let on):
            if on, m.state == .hidden {
                m.fullscreenActive && ctx.fullscreenPolicy == .hide ? (m.state = .suspended) : activate(&m, &fx)
            }
            if !on { m.state = .hidden }
        default: break
        }
    }

    private static func activate(_ m: inout SurfaceModel, _ fx: inout [SurfaceEffect]) {
        m.state = m.rest
        fx += [.updateGeometry, .showWindow]
    }

    private static func deactivate(_ m: inout SurfaceModel, to s: SurfaceState, _ fx: inout [SurfaceEffect]) {
        m.state = s; m.pointerInside = false; m.dragActive = false; m.pinned = false; m.openedExplicitly = false
        fx += [.cancelTimer(.hoverOpen), .cancelTimer(.hoverClose), .snap(toExpanded: false), .hideWindow]
    }

    private static func open(_ m: inout SurfaceModel, pinned: Bool, explicit: Bool, _ fx: inout [SurfaceEffect]) {
        m.state = .expanding(m.module)
        m.pinned = pinned
        m.openedExplicitly = explicit
        fx += [.cancelTimer(.hoverOpen), .cancelTimer(.hoverClose), .animate(toExpanded: true, .compactToExpanded)]
    }

    private static func close(_ m: inout SurfaceModel, _ fx: inout [SurfaceEffect]) {
        m.state = .collapsing
        m.pinned = false; m.openedExplicitly = false
        fx += [.cancelTimer(.hoverOpen), .cancelTimer(.hoverClose), .animate(toExpanded: false, .expandedToCompact)]
    }

    private static func retag(_ s: SurfaceState, _ mod: NotchModule) -> SurfaceState {
        if case .expanding = s { return .expanding(mod) }
        return .expanded(mod)
    }
}
