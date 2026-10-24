import Foundation
import Observation
import AuraCore

public enum SettingsError: Error, Equatable, Sendable {
    case invalid(String)
}

/// Almacén de ajustes sobre `UserDefaults` inyectable. Guarda por cambio con coalescencia.
@MainActor @Observable
public final class SettingsStore {
    public static let key = "aura.settings"

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue, !restoring else { return }
            undoStack.append(oldValue)
            if undoStack.count > 20 { undoStack.removeFirst() }
            scheduleSave()
        }
    }
    public private(set) var lastError: String?
    public var canUndo: Bool { !undoStack.isEmpty }
    /// Se invoca en `eraseAllData` para que otros módulos (shelf, historial) borren lo suyo.
    @ObservationIgnored public var onEraseAllData: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var undoStack: [AppSettings] = []
    @ObservationIgnored private var restoring = false
    /// Nº de escrituras reales a disco (para probar la coalescencia).
    @ObservationIgnored public private(set) var writeCount = 0

    public init(defaults: UserDefaults = .standard, saveDelay: Duration = .milliseconds(300)) {
        self.defaults = defaults
        self.saveDelay = saveDelay
        settings = Self.load(defaults) ?? AppSettings()
    }

    /// Clave donde se conserva el JSON original si no se pudo leer (p. ej. esquema de una versión futura):
    /// el `flush` posterior sobrescribiría el original con los valores por defecto.
    public static let backupKey = "aura.settings.unreadable-backup"

    private static func load(_ d: UserDefaults) -> AppSettings? {
        guard let data = d.data(forKey: key) else { return nil }
        if let ok = try? decode(data) { return ok }
        d.set(data, forKey: backupKey)
        return nil
    }

    /// Decodifica + migra + valida. Lanza sin tocar nada si es basura.
    static func decode(_ data: Data) throws -> AppSettings {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let migrated = SettingsMigration.migrate(obj),
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any],
              // Claves ausentes toman su valor por defecto.
              let clean = try? JSONSerialization.data(withJSONObject: base.merging(migrated) { _, new in new }),
              var s = try? JSONDecoder().decode(AppSettings.self, from: clean),
              s.validate() else { throw SettingsError.invalid(String(localized: "Los ajustes no son válidos o son de una versión más nueva.")) }
        // Ajustes guardados antes de existir el portapapeles: no lo activan por su cuenta.
        if let order = migrated["moduleOrder"] as? [String], !order.contains(NotchModule.clipboard.rawValue) {
            s.disabledModules.insert(.clipboard)
        }
        return s
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Guarda ya (cierre de la app, pruebas).
    public func flush() {
        saveTask?.cancel(); saveTask = nil
        guard let data = try? JSONEncoder().encode(settings) else { lastError = String(localized: "No se pudieron guardar los ajustes."); return }
        defaults.set(data, forKey: Self.key)
        writeCount += 1
    }

    /// Deshace el último cambio de ajustes (el propio deshacer no es deshacible, reset sí).
    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        restoring = true; settings = prev; restoring = false
        scheduleSave()
    }

    public func resetToDefaults() { settings = AppSettings() }

    public func exportJSON() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(settings)
    }

    /// Valida primero; si falla, los ajustes actuales quedan intactos.
    public func importJSON(_ data: Data) throws {
        do { settings = try Self.decode(data); lastError = nil }
        catch { lastError = String(localized: "Archivo de ajustes rechazado."); throw error }
    }

    /// Mueve un módulo (reordenación) manteniendo el orden completo sin duplicados.
    public func moveModules(from: IndexSet, to: Int) {
        var o = AppSettings.normalizedOrder(settings.moduleOrder)
        o.move(fromOffsets: from, toOffset: to)
        settings.moduleOrder = o
    }

    public func setModule(_ m: NotchModule, enabled: Bool) {
        if enabled { settings.disabledModules.remove(m) } else { settings.disabledModules.insert(m) }
    }

    /// Borrado completo: ajustes, claves `aura.*`, deshacer y datos de otros módulos vía callback.
    public func eraseAllData() {
        saveTask?.cancel(); saveTask = nil
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix("aura.") { defaults.removeObject(forKey: k) }
        undoStack.removeAll()
        restoring = true; settings = AppSettings(); restoring = false
        onEraseAllData?()
    }
}

extension Array {
    mutating func move(fromOffsets s: IndexSet, toOffset d: Int) {
        let moved = s.map { self[$0] }
        let before = s.filter { $0 < d }.count
        for i in s.reversed() { remove(at: i) }
        insert(contentsOf: moved, at: d - before)
    }
}
