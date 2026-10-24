import Foundation
import Observation
import SwiftUI

/// Tamaño preferido de la tarjeta (puntos). La vista usa el alto como mínimo y `columns` (1 o 2) como ancho en la rejilla.
public struct WidgetSize: Equatable, Sendable, Codable {
    public var width: Double, height: Double
    /// Columnas que ocupa en la rejilla de 2: 1 = media fila, 2 = fila entera.
    public var columns: Int
    public init(width: Double, height: Double, columns: Int = 1) { self.width = width; self.height = height; self.columns = columns }
    public static let small = WidgetSize(width: 200, height: 96)
    public static let medium = WidgetSize(width: 240, height: 132)
    /// Fila entera y baja (controles en línea: volumen).
    public static let wide = WidgetSize(width: 400, height: 64, columns: 2)
    /// Fila entera y alta (temporizador, acciones).
    public static let wideTall = WidgetSize(width: 400, height: 112, columns: 2)
}

/// Reparto de widgets en filas de una rejilla de 2 columnas, respetando el orden: los anchos van solos y los estrechos de dos en dos.
/// Un estrecho que se queda solo (porque el siguiente es ancho o es el último) ocupa la fila entera.
public enum WidgetGrid {
    public static func rows(columns: [Int]) -> [[Int]] {
        var rows: [[Int]] = [], pending: Int?
        for (i, c) in columns.enumerated() {
            if c >= 2 {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([i])
            } else if let p = pending { rows.append([p, i]); pending = nil }
            else { pending = i }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }
}

/// Permisos que un widget declara necesitar. Ninguno pide autorización al sistema por sí mismo.
public enum WidgetPermission: String, Equatable, Sendable, Codable {
    case openURLs          // abre URLs/carpetas con NSWorkspace
    case pasteboardWrite   // escribe en el portapapeles solo al pulsar una acción
    case notifications     // opcional; lo solicita y lo ejecuta el host, nunca el widget
}

public struct WidgetActionInfo: Equatable, Sendable, Identifiable {
    public var id: String, title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

/// Descripción declarativa de un widget.
public struct WidgetManifest: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var symbol: String
    public var preferredSize: WidgetSize
    public var permissions: [WidgetPermission]
    /// Intervalo mínimo entre actualizaciones en segundos; nil = solo por eventos (sin intervalo).
    public var minimumRefresh: TimeInterval?
    public var actions: [WidgetActionInfo]
    public init(id: String, name: String, version: String = "1.0", symbol: String, preferredSize: WidgetSize = .small,
                permissions: [WidgetPermission] = [], minimumRefresh: TimeInterval? = nil, actions: [WidgetActionInfo] = []) {
        self.id = id; self.name = name; self.version = version; self.symbol = symbol; self.preferredSize = preferredSize
        self.permissions = permissions; self.minimumRefresh = minimumRefresh; self.actions = actions
    }
}

/// Estados que todo widget declara (UI-09 / DoD §12).
public enum WidgetState: Equatable, Sendable {
    case empty(message: String)
    case loading
    case error(cause: String, solution: String)
    case ready
}

@MainActor public protocol AuraWidget: AnyObject {
    var manifest: WidgetManifest { get }
    var state: WidgetState { get }
    /// false = no existe en este sistema; el registro lo muestra deshabilitado y nunca lo activa.
    var isAvailable: Bool { get }
    /// Texto de VoiceOver con el estado actual de la tarjeta.
    var summary: String { get }
    /// true = visible y habilitado: es el único momento en que puede escuchar eventos. false = soltar todo.
    func setActive(_ active: Bool)
    func retry()
    func makeBody() -> AnyView
}

public extension AuraWidget {
    var isAvailable: Bool { true }
    func retry() {}
}

/// Orden y activación persistibles (el host los guarda donde quiera; aquí no se toca UserDefaults).
public struct WidgetLayout: Equatable, Sendable, Codable {
    public var order: [String]
    public var disabled: Set<String>
    public init(order: [String] = [], disabled: Set<String> = []) { self.order = order; self.disabled = disabled }
}

@MainActor @Observable
public final class WidgetRegistry {
    public struct Entry: Identifiable {
        public let widget: any AuraWidget
        public var enabled: Bool
        public let id: String
        @MainActor init(widget: any AuraWidget, enabled: Bool) { self.widget = widget; self.enabled = enabled; id = widget.manifest.id }
        /// Utilizable = habilitado + disponible.
        @MainActor public var isUsable: Bool { enabled && widget.isAvailable }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var isVisible = false
    @ObservationIgnored public var onLayoutChange: ((WidgetLayout) -> Void)?

    /// Los ids repetidos se ignoran. Con `layout` se aplica el orden guardado (los nuevos van al final).
    public init(widgets: [any AuraWidget], layout: WidgetLayout? = nil) {
        var seen = Set<String>()
        let unique = widgets.filter { seen.insert($0.manifest.id).inserted }
        let rank = Dictionary(uniqueKeysWithValues: (layout?.order ?? []).enumerated().map { ($1, $0) })
        let ordered = unique.enumerated().sorted {
            (rank[$0.element.manifest.id] ?? Int.max, $0.offset) < (rank[$1.element.manifest.id] ?? Int.max, $1.offset)
        }
        entries = ordered.map { Entry(widget: $0.element, enabled: !(layout?.disabled.contains($0.element.manifest.id) ?? false)) }
    }

    public var layout: WidgetLayout {
        WidgetLayout(order: entries.map(\.id), disabled: Set(entries.filter { !$0.enabled }.map(\.id)))
    }
    public func widget(_ id: String) -> (any AuraWidget)? { entries.first { $0.id == id }?.widget }
    public func isEnabled(_ id: String) -> Bool { entries.first { $0.id == id }?.enabled ?? false }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].enabled != enabled else { return }
        entries[i].enabled = enabled
        sync(i); changed()
    }

    public func canMove(_ id: String, by offset: Int) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        return entries.indices.contains(i + offset) && offset != 0
    }

    public func move(_ id: String, by offset: Int) {
        guard canMove(id, by: offset), let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.insert(entries.remove(at: i), at: i + offset)
        changed()
    }

    /// El host (o `WidgetsView`) avisa de la visibilidad; fuera de pantalla ningún widget escucha eventos.
    public func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        entries.indices.forEach(sync)
    }

    private func sync(_ i: Int) { entries[i].widget.setActive(isVisible && entries[i].isUsable) }
    private func changed() { onLayoutChange?(layout) }
}
