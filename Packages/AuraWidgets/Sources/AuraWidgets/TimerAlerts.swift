import AppKit
import Foundation
@preconcurrency import UserNotifications

/// Sonido de aviso (inyectable: las pruebas no tocan el sistema).
@MainActor public protocol TimerSound {
    func playFinished()
}

/// Sonido breve de sistema. «Glass» existe en /System/Library/Sounds de macOS; si no, pitido estándar.
public struct SystemTimerSound: TimerSound {
    public init() {}
    public func playFinished() { if NSSound(named: "Glass")?.play() != true { NSSound.beep() } }
}

public enum TimerNotificationAuth: Equatable, Sendable { case notDetermined, authorized, denied }

/// Centro de notificaciones (inyectable). Las pruebas usan un doble; el real es `UserNotificationCenterAdapter`.
@MainActor public protocol TimerNotificationCenter: AnyObject {
    func authorization() async -> TimerNotificationAuth
    /// Muestra el diálogo del sistema. true = concedido.
    func requestAuthorization() async -> Bool
    func post(title: String, body: String) async
}

/// Notificación del sistema real. `UNUserNotificationCenter.current()` lanza una excepción sin bundle
/// (p. ej. `swift run`), por eso `init` devuelve nil si la app no está empaquetada.
@MainActor public final class UserNotificationCenterAdapter: NSObject, TimerNotificationCenter, UNUserNotificationCenterDelegate {
    public init?(bundle: Bundle = .main) {
        guard bundle.bundleIdentifier != nil else { return nil }
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    public func authorization() async -> TimerNotificationAuth {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }
    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }
    public func post(title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body  // sin sonido propio: ya suena `TimerSound`
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "aura.timer.finished", content: c, trigger: nil))
    }
    // La app es de barra/notch: casi siempre "en primer plano", así que sin esto el banner no saldría.
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

/// Aviso completo del temporizador: sonido siempre; notificación solo si hay centro y está autorizado.
/// El permiso se pide la PRIMERA vez que se inicia un temporizador (estado `.notDetermined`), nunca al arrancar.
/// Si se deniega, solo queda el sonido.
@MainActor public final class SystemTimerNotifier: TimerNotifier {
    private let sound: any TimerSound
    private let center: (any TimerNotificationCenter)?

    /// `center` nil = app sin empaquetar: solo sonido.
    public init(sound: any TimerSound = SystemTimerSound(), center: (any TimerNotificationCenter)? = UserNotificationCenterAdapter()) {
        self.sound = sound; self.center = center
    }

    public var usesSystemNotifications: Bool { center != nil }

    public func timerStarted(duration: TimeInterval) {
        guard let center else { return }
        Task { if await center.authorization() == .notDetermined { _ = await center.requestAuthorization() } }
    }

    public func timerFinished(duration: TimeInterval) {
        sound.playFinished()
        guard let center else { return }
        Task {
            guard await center.authorization() == .authorized else { return }
            await center.post(title: WidgetStrings.finishedTitle, body: WidgetStrings.finishedBody(WidgetStrings.spoken(duration)))
        }
    }
}
