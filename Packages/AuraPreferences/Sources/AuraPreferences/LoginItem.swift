import Foundation
import ServiceManagement

/// Envoltorio de `SMAppService.mainApp`.
/// Limitación: solo funciona con la app empaquetada (.app firmada); con `swift run` el registro
/// falla y se devuelve un estado/mensaje legible en vez de lanzar.
public enum LoginItem {
    public enum State: Equatable, Sendable {
        case enabled, disabled, requiresApproval
        case unavailable(String)
    }

    static var isPackaged: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    public static var state: State {
        guard isPackaged else { return .unavailable(String(localized: "Disponible solo con la app empaquetada (.app).")) }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable(String(localized: "No se encontró la app para registrar el inicio."))
        @unknown default: return .unavailable(String(localized: "Estado desconocido."))
        }
    }

    /// Devuelve el estado resultante; nunca lanza.
    @discardableResult
    public static func setEnabled(_ on: Bool) -> State {
        guard isPackaged else { return state }
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { return .unavailable(String(localized: "No se pudo cambiar el inicio de sesión: \(error.localizedDescription)")) }
        return state
    }
}
