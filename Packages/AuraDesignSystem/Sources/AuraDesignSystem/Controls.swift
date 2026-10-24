import AuraCore
import SwiftUI

// Estados de control (§3.1): normal, hover, pressed, focus, disabled, loading, success, error.

public enum ControlState: CaseIterable, Sendable {
    case normal, hover, pressed, focus, disabled, loading, success, error
}

/// Estado de la operación que el control representa (lo decide quien lo usa).
public enum ControlStatus: Sendable { case idle, loading, success, error }

public enum ControlEmphasis: Sendable { case secondary, primary, filled }

/// Colores de un control en un estado: función pura, medible en pruebas.
public struct ControlAppearance: Equatable, Sendable {
    public var foreground: TokenColor
    public var background: TokenColor?
    public var foregroundOpacity: Double
    public var showsFocusRing: Bool

    public static func resolve(_ state: ControlState, emphasis: ControlEmphasis) -> ControlAppearance {
        let base: TokenColor = emphasis == .secondary ? AuraColor.secondaryText : AuraColor.primaryText
        let rest: TokenColor? = emphasis == .filled ? AuraColor.elevatedSurface : nil
        func make(_ fg: TokenColor, _ bg: TokenColor?, opacity: Double = 1, ring: Bool = false) -> ControlAppearance {
            ControlAppearance(foreground: fg, background: bg, foregroundOpacity: opacity, showsFocusRing: ring)
        }
        switch state {
        case .normal: return make(base, rest)
        case .hover: return make(AuraColor.primaryText, AuraColor.elevatedSurface)
        case .pressed: return make(AuraColor.primaryText, AuraColor.pressedSurface)
        case .focus: return make(AuraColor.primaryText, rest, ring: true)
        case .disabled: return make(AuraColor.secondaryText, rest, opacity: 0.4)
        case .loading: return make(AuraColor.secondaryText, rest)
        case .success: return make(AuraColor.success, rest)
        case .error: return make(AuraColor.destructive, rest)
        }
    }
}

/// Vista pura de un control en un estado concreto. `ButtonStyle` la usa con el estado real;
/// la galería de pruebas la usa con estados forzados.
public struct ControlChrome<Label: View>: View {
    let state: ControlState
    let emphasis: ControlEmphasis
    let ring: Bool
    let label: Label
    @Environment(\.auraAccent) private var accent

    public init(state: ControlState, emphasis: ControlEmphasis = .secondary, ring: Bool? = nil,
                @ViewBuilder label: () -> Label) {
        self.state = state; self.emphasis = emphasis; self.label = label()
        self.ring = ring ?? (state == .focus)
    }

    public var body: some View {
        let look = ControlAppearance.resolve(state, emphasis: emphasis)
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        content
            .foregroundStyle(look.foreground.color.opacity(look.foregroundOpacity))
            .padding(.horizontal, Space.sm)
            .frame(minWidth: 28, minHeight: 28)
            .background { if let bg = look.background { shape.fill(bg.color) } }
            .overlay { if ring { shape.strokeBorder(accent ?? AuraColor.accent.color, lineWidth: 2) } }
            .contentShape(shape)
            .accessibilityValue(statusText)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading: ProgressView().controlSize(.small)
        case .success: Image(systemName: "checkmark")
        case .error: Image(systemName: "exclamationmark.triangle")
        default: label
        }
    }

    private var statusText: String {
        switch state {
        case .loading: Strings.loading
        case .success: Strings.success
        case .error: Strings.failure
        default: ""
        }
    }
}

/// Estilo para botones de icono o texto del panel. Estados reales: hover, pressed, focus
/// (teclado), disabled (`.disabled`) y los de operación vía `status`.
public struct AuraButtonStyle: ButtonStyle {
    public var emphasis: ControlEmphasis
    public var status: ControlStatus

    public init(emphasis: ControlEmphasis = .secondary, status: ControlStatus = .idle) {
        self.emphasis = emphasis; self.status = status
    }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, emphasis: emphasis, status: status)
    }

    private struct Styled: View {
        let configuration: ButtonStyle.Configuration
        let emphasis: ControlEmphasis
        let status: ControlStatus
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false
        private let motion = MotionEnvironment()

        private var state: ControlState {
            if !isEnabled { return .disabled }
            switch status {
            case .loading: return .loading
            case .success: return .success
            case .error: return .error
            case .idle: break
            }
            if configuration.isPressed { return .pressed }
            if hovering { return .hover }
            return isFocused ? .focus : .normal
        }

        var body: some View {
            ControlChrome(state: state, emphasis: emphasis, ring: isFocused && isEnabled) { configuration.label }
                .onHover { hovering = $0 }
                .animation(Motion.animation(.actionCompleted, motion.value), value: state)
        }
    }
}
