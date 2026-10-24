import Foundation

/// Módulos navegables del panel expandido.
public enum NotchModule: String, CaseIterable, Sendable, Codable {
    case home, media, shelf, calendar, widgets, clipboard
}

/// Actividad dominante del estado compacto (máximo una a la vez, §3.4).
public enum ActivityKind: Equatable, Sendable {
    case media(playing: Bool)
    case transfer
    case timer
    case alert
    case error
}

/// Estados de la superficie (§4.4). `expanding`/`collapsing` llevan el destino
/// para poder reorientar una transición en vuelo (invariante: interrumpible).
public enum SurfaceState: Equatable, Sendable {
    case hidden
    case idle
    case compact(ActivityKind)
    case expanding(NotchModule)
    case expanded(NotchModule)
    case collapsing
    case suspended
}

/// Eventos de entrada de la máquina de estados (§4.4).
public enum SurfaceEvent: Equatable, Sendable {
    case pointerEnter, pointerExit, click, hotkey
    case activityChanged(ActivityKind?)
    case dragEntered, dragExited, drop
    case escape
    case screenChanged, fullscreenChanged(Bool), permissionChanged
    case selectModule(NotchModule)
    case transitionFinished
    case setEnabled(Bool)
}

/// Preferencia de movimiento efectiva (sistema + ajustes de la app, §4.2.6).
public enum MotionPreference: Equatable, Sendable {
    case full, reduced, none
}

/// Modos de anclaje (§3.3).
public enum SurfaceMode: String, Sendable, Codable {
    case notch, topCenterFloating, disabledOnExternalDisplay
}
