import Foundation

/// Catálogo de transiciones. Duraciones iniciales en segundos;
/// ajustables tras prototipado en hardware real.
public enum Transition: String, CaseIterable, Sendable {
    case idleToCompact       // AN-01
    case compactToExpanded   // AN-02
    case expandedToCompact   // AN-03
    case switchModule        // AN-04
    case newActivity         // AN-05
    case dragOverShelf       // AN-06
    case dropAccepted        // AN-07
    case reorder             // AN-08
    case actionCompleted     // AN-09
    case error               // AN-10
    case timerFinished       // AN-11

    public var duration: TimeInterval {
        switch self {
        case .idleToCompact: 0.150
        case .compactToExpanded: 0.260
        case .expandedToCompact: 0.240
        case .switchModule: 0.180
        case .newActivity: 0.200
        case .dragOverShelf: 0.140
        case .dropAccepted: 0.220
        case .reorder: 0.200
        case .actionCompleted: 0.160
        case .error: 0.150
        case .timerFinished: 0.250
        }
    }

    /// AN-12: con Reduce Motion ≤120 ms (fade); con `.none` instantáneo.
    public func duration(for preference: MotionPreference) -> TimeInterval {
        switch preference {
        case .full: duration
        case .reduced: min(duration, 0.120)
        case .none: 0
        }
    }
}
