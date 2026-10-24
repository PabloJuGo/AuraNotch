import AppKit
import CoreGraphics

/// Una ventana tal y como la ve `CGWindowListCopyWindowInfo` (sin títulos: exigirían Screen Recording).
/// `bounds` en coordenadas CG (origen arriba-izquierda), igual que `CGDisplayBounds`.
public struct WindowSample: Equatable, Sendable {
    public var owner: String
    public var pid: Int32
    public var layer: Int
    public var bounds: CGRect
    /// Solo si el sistema lo expone; la heurística no depende de él.
    public var name: String?
    public init(owner: String, pid: Int32, layer: Int, bounds: CGRect, name: String? = nil) {
        self.owner = owner; self.pid = pid; self.layer = layer; self.bounds = bounds; self.name = name
    }
}

/// Heurística pura (probada con ventanas sintéticas). Ver Docs/decisions/0003-fullscreen-teclado-alas-tamano.md.
///
/// Medido en este Mac (macOS 27, notch): una app a pantalla completa nativa mide (0,34,w,h-34), IDÉNTICO a una
/// ventana maximizada, así que la geometría de la app NO sirve. Lo que sí cambia es que el sistema crea una ventana
/// de WindowManager llamada «Fullscreen Backdrop» en el nivel `desktopWindow + 1` mientras el Space activo es de
/// pantalla completa (y no existe en el escritorio normal).
public enum FullscreenHeuristic {
    /// Nivel observado del backdrop: justo encima del fondo de escritorio (`desktopWindow` = INT_MIN + 25).
    public static let backdropLayer = Int(CGWindowLevelForKey(.desktopWindow)) + 1

    public static func isFullscreen(windows: [WindowSample], display: CGRect, ownPID: Int32) -> Bool {
        windows.contains { w in
            // Solo cuenta lo que cubre entera la pantalla del panel (1 pt de tolerancia) y no es nuestro.
            guard w.pid != ownPID, w.bounds.insetBy(dx: -1, dy: -1).contains(display) else { return false }
            // R1: backdrop del sistema (pantalla completa nativa / Split View). Capa exacta o, si hay nombre, el nombre.
            if w.owner == "WindowManager", w.layer == backdropLayer || w.name == "Fullscreen Backdrop" { return true }
            // R2: ventana normal de otra app que cubre TODA la pantalla incluida la franja de la barra de menús
            // (pantalla completa "a mano": juegos, presentaciones, kiosco). Una ventana maximizada empieza bajo la barra.
            return w.layer == 0
        }
    }
}

/// Fuente de la señal "hay una app a pantalla completa en la pantalla del panel". Sin permisos, sin polling.
@MainActor public protocol FullscreenDetector: AnyObject {
    /// Empieza a observar y entrega el veredicto inicial y cada cambio posterior (nunca repite el mismo valor).
    func start(_ onChange: @escaping @MainActor (Bool) -> Void)
    func stop()
}

/// Implementación real: reevalúa solo ante eventos (cambio de Space, app activa, pantallas, despertar)
/// con una segunda lectura diferida, porque el backdrop aparece/desaparece unos ms después de la notificación.
@MainActor public final class SystemFullscreenDetector: FullscreenDetector {
    private let display: () -> CGRect?
    private let windows: () -> [WindowSample]
    private let settle: [TimeInterval]
    private var onChange: (@MainActor (Bool) -> Void)?
    private var last: Bool?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var settleTimers: [Timer] = []

    /// `settle`: lecturas diferidas tras cada evento (medido: el backdrop tarda ~0,4 s en desaparecer al salir).
    public init(settle: [TimeInterval] = [0.4, 1.2], display: (() -> CGRect?)? = nil, windows: (() -> [WindowSample])? = nil) {
        self.settle = settle
        self.display = display ?? { SystemFullscreenDetector.targetDisplayBounds() }
        self.windows = windows ?? { SystemFullscreenDetector.onScreenWindows() }
    }

    public func start(_ onChange: @escaping @MainActor (Bool) -> Void) {
        stop()
        self.onChange = onChange
        last = nil
        let ws = NSWorkspace.shared.notificationCenter
        let names: [(NotificationCenter, Notification.Name)] = [
            (ws, NSWorkspace.activeSpaceDidChangeNotification), (ws, NSWorkspace.didActivateApplicationNotification),
            (ws, NSWorkspace.didWakeNotification), (ws, NSWorkspace.screensDidWakeNotification),
            (.default, NSApplication.didChangeScreenParametersNotification)]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventArrived() }
            }
            observers.append((center, token))
        }
        evaluate()
    }

    public func stop() {
        for (c, o) in observers { c.removeObserver(o) }
        observers = []
        settleTimers.forEach { $0.invalidate() }; settleTimers = []
        onChange = nil
    }

    /// Una lectura inmediata y varias diferidas (las ráfagas de eventos se coalescen).
    private func eventArrived() {
        evaluate()
        settleTimers.forEach { $0.invalidate() }
        settleTimers = settle.map { delay in
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
    }

    private func evaluate() {
        guard let onChange, let d = display() else { return }
        let now = FullscreenHeuristic.isFullscreen(windows: windows(), display: d, ownPID: ProcessInfo.processInfo.processIdentifier)
        guard now != last else { return }
        last = now
        onChange(now)
    }

    // MARK: - Fuentes reales

    /// Límites CG de la pantalla donde vive el panel.
    static func targetDisplayBounds() -> CGRect? {
        guard let id = SurfaceWindowController.targetScreen()?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        return CGDisplayBounds(id)
    }

    /// OJO: sin `.excludeDesktopElements`: el backdrop vive en un nivel de escritorio.
    static func onScreenWindows() -> [WindowSample] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let d = w[kCGWindowBounds as String] as? NSDictionary, let b = CGRect(dictionaryRepresentation: d as CFDictionary) else { return nil }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil } // transparente: no tapa nada
            return WindowSample(owner: w[kCGWindowOwnerName as String] as? String ?? "",
                                pid: (w[kCGWindowOwnerPID as String] as? Int32) ?? 0,
                                layer: (w[kCGWindowLayer as String] as? Int) ?? 0, bounds: b,
                                name: w[kCGWindowName as String] as? String)
        }
    }
}
