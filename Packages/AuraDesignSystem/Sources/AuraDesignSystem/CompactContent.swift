import AuraCore
import SwiftUI

extension ActivityKind {
    public var symbolName: String {
        switch self {
        case .media(let playing): playing ? "waveform" : "pause.fill"
        case .transfer: "arrow.down.circle"
        case .timer: "timer"
        case .alert: "bell.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: TokenColor { self == .error ? AuraColor.warning : AuraColor.primaryText }
}

/// Contenido del estado compacto (§3.4): icono de la ÚNICA actividad dominante a la izquierda,
/// texto muy breve (o progreso) a la derecha, y un hueco central para el notch físico.
/// `activity == nil` (idle) no dibuja nada y se oculta a VoiceOver.
public struct CompactContent: View {
    let activity: ActivityKind?
    let detail: String?
    let progress: Double?
    let centerGap: CGFloat
    @Environment(\.auraAccent) private var accent
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - detail: texto muy breve (se trunca a una línea).
    ///   - progress: 0...1 opcional; se dibuja como anillo fino, sin animación propia.
    ///   - centerGap: ancho reservado al notch físico (`safeAreaInsets`/área auxiliar).
    public init(activity: ActivityKind?, detail: String? = nil, progress: Double? = nil, centerGap: CGFloat = 0) {
        self.activity = activity; self.detail = detail; self.progress = progress; self.centerGap = centerGap
    }

    public var body: some View {
        if let activity {
            HStack(spacing: 0) {
                icon(activity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: centerGap)
                trailing
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Space.md)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(activity))
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private var isPlayingWaves: Bool {
        activity == .media(playing: true) && MotionPreference.resolve(override: motionOverride, systemReduceMotion: reduceMotion) == .full
    }

    /// Icono de la actividad. Sonando y con movimiento completo, ecualizador animado; si no, el símbolo estático.
    @ViewBuilder private func icon(_ activity: ActivityKind) -> some View {
        let color = activity == .error ? activity.tint.color : accent ?? activity.tint.color
        if isPlayingWaves {
            WaveBars(color: color).frame(width: 14, height: WaveBarsView.height)
        } else {
            Image(systemName: activity.symbolName).font(AuraFont.compact).foregroundStyle(color)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let progress {
            ProgressRing(value: min(max(progress, 0), 1))
                .frame(width: 14, height: 14)
        } else if let detail {
            Text(detail)
                .font(AuraFont.numeric)
                .foregroundStyle(AuraColor.secondaryText.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    func accessibilityText(_ a: ActivityKind) -> String {
        [Strings.activity(a), detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Anillo de progreso estático (sin animación continua).
struct ProgressRing: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(AuraColor.separator.color, lineWidth: 2)
            Circle().trim(from: 0, to: value)
                .stroke(AuraColor.primaryText.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
