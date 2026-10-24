import Foundation
import Observation

/// Aviso breve de la propia app para el notch cerrado (nunca de otras apps: no hay API pública).
public struct AuraAlert: Equatable, Sendable {
    public var symbol: String
    /// Texto muy corto (cabe en el ala del notch).
    public var text: String
    /// Frase completa para VoiceOver; si es nil se lee `text`.
    public var spoken: String?
    public init(symbol: String, text: String, spoken: String? = nil) {
        self.symbol = symbol; self.text = text; self.spoken = spoken
    }
}

/// Un solo aviso visible a la vez; el último gana. Se retira solo, sin temporizadores periódicos.
@MainActor @Observable public final class AlertCenter {
    public private(set) var current: AuraAlert?
    public var enabled = true { didSet { if !enabled { dismiss() } } }
    private var task: Task<Void, Never>?

    public init() {}

    public func post(_ alert: AuraAlert, for duration: Duration = .seconds(5)) {
        guard enabled else { return }
        task?.cancel()
        current = alert
        task = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    public func dismiss() { task?.cancel(); task = nil; current = nil }
}
