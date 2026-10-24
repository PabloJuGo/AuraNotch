import Foundation

/// Marca de «onboarding visto». `UserDefaults` inyectable. La clave empieza por `aura.`, así que
/// «Borrar todos los datos» (SettingsStore.eraseAllData) también la limpia y vuelve a mostrarse.
public struct OnboardingState {
    public static let key = "aura.onboarding.done"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isDone: Bool { defaults.bool(forKey: Self.key) }
    /// Primera vez = true; usuario de retorno = false.
    public var shouldShow: Bool { !isDone }
    /// Se llama tanto al completar como al omitir o cerrar la ventana: el usuario ya decidió.
    public func markDone() { defaults.set(true, forKey: Self.key) }
    public func reset() { defaults.removeObject(forKey: Self.key) }
}

/// Pasos del onboarding; lógica pura de navegación.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, privacy, modules
    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }
}
