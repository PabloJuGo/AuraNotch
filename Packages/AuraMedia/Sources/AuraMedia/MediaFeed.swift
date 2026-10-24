import AppKit
import AuraCore
import Foundation

/// Fuente de eventos de reproducción sin permisos. nil = fuente perdida (detenido o app cerrada).
public protocol PlayerFeed: Sendable {
    func events(notification: String, bundleID: String) -> AsyncStream<MediaItem?>
}

private final class ObserverTokens: @unchecked Sendable {
    let tokens: [(NotificationCenter, NSObjectProtocol)]
    init(_ t: [(NotificationCenter, NSObjectProtocol)]) { tokens = t }
    func remove() { tokens.forEach { $0.0.removeObserver($0.1) } }
}

/// `DistributedNotificationCenter` + cierre de la app (NSWorkspace). Observar no requiere permiso.
public struct DistributedPlayerFeed: PlayerFeed {
    public init() {}

    public func events(notification: String, bundleID: String) -> AsyncStream<MediaItem?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { cont in
            let dnc = DistributedNotificationCenter.default()
            let ws = NSWorkspace.shared.notificationCenter
            let a = dnc.addObserver(forName: Notification.Name(notification), object: nil, queue: nil) { n in
                switch PlayerPayload.parse(n.userInfo ?? [:]) {
                case .item(let item): cont.yield(item)
                case .stopped: cont.yield(nil)
                case .invalid: break
                }
            }
            let b = ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == bundleID { cont.yield(nil) }
            }
            let tokens = ObserverTokens([(dnc, a), (ws, b)])
            cont.onTermination = { _ in tokens.remove() }
        }
    }
}
