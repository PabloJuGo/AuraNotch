import AppKit
import Foundation
import Observation

/// Resultado de resolver un bookmark (fuera del MainActor).
public struct ShelfResolved: Sendable {
    public var url: URL
    /// Bookmark renovado si el anterior estaba `stale`.
    public var fresh: Data?
    public init(url: URL, fresh: Data? = nil) { self.url = url; self.fresh = fresh }
}

/// E/S de disco/red de la shelf. Se ejecuta SIEMPRE fuera del MainActor (§6.5); inyectable para pruebas.
public struct ShelfIO: Sendable {
    /// nil si el archivo no existe o no admite bookmark.
    public var bookmark: @Sendable (URL) -> Data?
    /// Clave canónica de duplicado.
    public var key: @Sendable (URL) -> String
    /// nil si falta (borrado, Papelera, volumen desmontado).
    public var resolve: @Sendable (Data) -> ShelfResolved?

    public init(bookmark: @escaping @Sendable (URL) -> Data?, key: @escaping @Sendable (URL) -> String,
                resolve: @escaping @Sendable (Data) -> ShelfResolved?) {
        self.bookmark = bookmark; self.key = key; self.resolve = resolve
    }

    public static let live = ShelfIO(
        bookmark: { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? url.bookmarkData()
        },
        key: { url in
            let real = url.resolvingSymlinksInPath()
            let canon = (try? real.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath
            return "file:" + (canon ?? real.path)
        },
        resolve: { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path),
                  !url.pathComponents.contains(".Trash")
            else { return nil }
            return ShelfResolved(url: url, fresh: stale ? try? url.bookmarkData() : nil)
        })
}

/// Efectos sobre el sistema, inyectables para pruebas. Ninguno modifica el original.
@MainActor
public struct ShelfSystem {
    public var open: (URL) -> Bool
    public var reveal: ([URL]) -> Void
    public var pasteboard: NSPasteboard
    public var io: ShelfIO

    public init(open: @escaping (URL) -> Bool, reveal: @escaping ([URL]) -> Void, pasteboard: NSPasteboard,
                io: ShelfIO = .live) {
        self.open = open; self.reveal = reveal; self.pasteboard = pasteboard; self.io = io
    }

    public static var live: ShelfSystem {
        ShelfSystem(open: { NSWorkspace.shared.open($0) },
                    reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) },
                    pasteboard: .general)
    }
}

/// Estantería de referencias. Temporal (solo memoria) por defecto; la persistencia es opt-in.
@MainActor @Observable
public final class ShelfService {
    public static let maxHistoryLimit = 500

    /// Orden de inserción: el más nuevo al final.
    public private(set) var items: [ShelfItem] = []
    public private(set) var states: [UUID: ShelfItemState] = [:]
    public var selection: Set<UUID> = []
    public private(set) var dropState: ShelfDropState = .idle
    public private(set) var isPersistent = false
    public private(set) var historyLimit: Int
    public var loadIssue: ShelfLoadIssue?
    public private(set) var writeError: String?

    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private let system: ShelfSystem
    @ObservationIgnored private let writer = ShelfWriter()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    @ObservationIgnored private var anchor: UUID?
    @ObservationIgnored private var acceptedReset: Task<Void, Never>?
    /// Clave canónica de duplicado por elemento (calculada fuera del MainActor).
    @ObservationIgnored private var fileKeys: [UUID: String] = [:]
    /// Elementos soltados cuyo bookmark aún se está creando (visibles, pero no persistibles ni comparables).
    @ObservationIgnored private var pendingIDs: Set<UUID> = []
    @ObservationIgnored private var addTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    /// Persistencia deseada (isPersistent solo sube a true cuando la carga terminó y se fusionó).
    @ObservationIgnored private var wantsPersistence = false

    public init(storageURL: URL? = nil, historyLimit: Int = 50, persistent: Bool = false,
                system: ShelfSystem = .live) {
        self.storageURL = storageURL ?? ShelfStorage.defaultURL
        self.historyLimit = min(max(historyLimit, 1), Self.maxHistoryLimit)
        self.system = system
        if persistent { setPersistence(true) }
    }

    public func state(of id: UUID) -> ShelfItemState { states[id] ?? .missing }

    /// URL de trabajo: archivo resuelto o URL web. nil si falta.
    public func url(for item: ShelfItem) -> URL? {
        if case .available(let u) = state(of: item.id) { return u }
        return nil
    }

    // MARK: - Alta

    /// Añade referencias sin tocar disco en el MainActor: los archivos aparecen ya (optimistas) y su
    /// bookmark/duplicado se resuelven en segundo plano. El resultado devuelto es optimista: los
    /// archivos inexistentes o duplicados de archivo se retiran después. Para el resultado exacto: `addResolved`.
    @discardableResult
    public func add(urls: [URL]) -> ShelfAddResult {
        let (result, pending) = stage(urls)
        launchFinalize(pending)
        return result
    }

    /// Igual que `add(urls:)` pero espera a la E/S y devuelve el resultado exacto.
    @discardableResult
    public func addResolved(urls: [URL]) async -> ShelfAddResult {
        var (result, pending) = stage(urls)
        let fin = await finalize(pending)
        result.added.removeAll { fin.removed.contains($0.id) }
        result.duplicates += fin.duplicates
        result.rejected += fin.rejected
        return result
    }

    /// Fase síncrona y sin E/S: web (dedup por URL) y archivos optimistas.
    private func stage(_ urls: [URL]) -> (ShelfAddResult, [(item: ShelfItem, url: URL, raw: URL)]) {
        var result = ShelfAddResult()
        var pending: [(item: ShelfItem, url: URL, raw: URL)] = []
        var webKeys: [String: UUID] = [:]
        for it in items where it.kind == .web { if let k = key(of: it) { webKeys[k] = it.id } }

        for raw in urls {
            if raw.isFileURL {
                let url = (raw as NSURL).filePathURL ?? raw
                let item = ShelfItem(name: url.lastPathComponent, kind: .file, lastKnownPath: url.path)
                states[item.id] = .available(url)
                pendingIDs.insert(item.id)
                items.append(item)
                result.added.append(item)
                pending.append((item, url, raw))
            } else if let s = raw.scheme?.lowercased(), s == "http" || s == "https" {
                let key = "web:" + raw.absoluteString
                if let dup = webKeys[key] { result.duplicates.append(dup); continue }
                let item = ShelfItem(name: Self.webName(raw), kind: .web, webURL: raw)
                states[item.id] = .available(raw)
                webKeys[key] = item.id
                items.append(item)
                result.added.append(item)
            } else { result.rejected.append(raw) }
        }
        trim()
        if !result.added.isEmpty { persist(); flashAccepted(result.added.count) }
        return (result, pending)
    }

    private func launchFinalize(_ pending: [(item: ShelfItem, url: URL, raw: URL)]) {
        guard !pending.isEmpty else { return }
        let token = UUID()
        addTasks[token] = Task { [weak self] in
            _ = await self?.finalize(pending)
            self?.addTasks[token] = nil
        }
    }

    /// Crea bookmarks y claves fuera del MainActor y los aplica de vuelta. La deduplicación se decide
    /// aquí, en serie en el MainActor, así que dos lotes en vuelo no pueden duplicarse entre sí.
    private func finalize(_ pending: [(item: ShelfItem, url: URL, raw: URL)])
        async -> (removed: Set<UUID>, duplicates: [UUID], rejected: [URL]) {
        guard !pending.isEmpty else { return ([], [], []) }
        let io = system.io
        let jobs = pending.map { ($0.item.id, $0.url) }
        let out: [(UUID, Data, String)?] = await Task.detached {
            jobs.map { id, url in io.bookmark(url).map { (id, $0, io.key(url)) } }
        }.value

        var removed = Set<UUID>(), dups: [UUID] = [], rejected: [URL] = []
        var changed = false
        for (n, p) in pending.enumerated() {
            let id = p.item.id
            guard let i = items.firstIndex(where: { $0.id == id }) else { pendingIDs.remove(id); continue }
            guard let (_, data, newKey) = out[n] else {
                items.remove(at: i); states[id] = nil; selection.remove(id); pendingIDs.remove(id)
                removed.insert(id); rejected.append(p.raw); continue
            }
            pendingIDs.remove(id)
            if let owner = items.first(where: { $0.id != id && !pendingIDs.contains($0.id) && key(of: $0) == newKey }) {
                items.remove(at: i); states[id] = nil; selection.remove(id)
                removed.insert(id); dups.append(owner.id); continue
            }
            items[i].bookmarkData = data
            fileKeys[id] = newKey
            changed = true
        }
        if changed { persist() }
        return (removed, dups, rejected)
    }

    /// Lee URLs de un pasteboard de arrastre (para el host que recibe el drop en la ventana del notch).
    @discardableResult
    public func add(pasteboard: NSPasteboard) -> ShelfAddResult {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        return add(urls: urls)
    }

    // MARK: - Resolución

    /// Re-resuelve todas las referencias (llamar al mostrar la shelf). No bloquea; si ya hay una en
    /// curso no encola otra. Refresca bookmarks `stale`.
    public func refresh() { _ = startRefresh() }

    /// Como `refresh()` pero espera a que termine (pruebas).
    public func refreshAndWait() async { await startRefresh().value }

    private func startRefresh() -> Task<Void, Never> {
        if let t = refreshTask { return t }
        let t = Task { [weak self] in
            await self?.resolveItems(nil)
            self?.refreshTask = nil
        }
        refreshTask = t
        return t
    }

    /// Recuperación de un elemento ausente: re-resuelve. true si vuelve a estar disponible.
    @discardableResult
    public func recover(_ id: UUID) async -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        await resolveItems([id])
        if case .available = state(of: id) { return true }
        return false
    }

    /// Resuelve bookmarks fuera del MainActor y aplica el resultado. `ids == nil` = todos.
    private func resolveItems(_ ids: Set<UUID>?) async {
        var jobs: [(UUID, Data)] = []
        for it in items where ids?.contains(it.id) ?? true {
            if it.kind == .web { states[it.id] = it.webURL.map { .available($0) } ?? .missing }
            else if pendingIDs.contains(it.id) { continue }
            else if let d = it.bookmarkData { jobs.append((it.id, d)) }
            else { states[it.id] = .missing }
        }
        guard !jobs.isEmpty else { return }
        let io = system.io
        let out: [(UUID, ShelfResolved?, String?)] = await Task.detached {
            jobs.map { id, d in let r = io.resolve(d); return (id, r, r.map { io.key($0.url) }) }
        }.value

        var changed = false
        for (id, r, key) in out {
            guard let i = items.firstIndex(where: { $0.id == id }), !pendingIDs.contains(id) else { continue }
            guard let r else { states[id] = .missing; continue }
            states[id] = .available(r.url)
            fileKeys[id] = key
            if let fresh = r.fresh { items[i].bookmarkData = fresh; changed = true }
            if items[i].lastKnownPath != r.url.path { items[i].lastKnownPath = r.url.path; changed = true }
        }
        if changed { persist() }
    }

    // MARK: - Selección

    public func select(_ id: UUID, extend: Bool = false, range: Bool = false) {
        if range, let a = anchor, let x = items.firstIndex(where: { $0.id == a }),
           let y = items.firstIndex(where: { $0.id == id }) {
            let ids = items[min(x, y)...max(x, y)].map(\.id)
            selection = extend ? selection.union(ids) : Set(ids)
        } else if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else { selection = [id]; anchor = id }
    }

    public func selectAll() { selection = Set(items.map(\.id)) }
    public func clearSelection() { selection = []; anchor = nil }

    /// Convención de Finder: si el elemento pertenece a la selección actúa toda; si no, solo él.
    public func ids(forContextOf id: UUID) -> [UUID] {
        selection.contains(id) ? items.map(\.id).filter(selection.contains) : [id]
    }

    // MARK: - Acciones (por lote; ninguna toca el original)

    private func resolved(_ ids: [UUID]) -> [(ShelfItem, URL)] {
        let set = Set(ids)
        return items.compactMap { it in set.contains(it.id) ? url(for: it).map { (it, $0) } : nil }
    }

    /// Abre archivos con su app por defecto y enlaces en el navegador. Devuelve cuántos.
    @discardableResult
    public func open(_ ids: [UUID]) -> Int { resolved(ids).filter { system.open($0.1) }.count }

    /// Muestra en Finder los archivos (los enlaces web se ignoran).
    @discardableResult
    public func reveal(_ ids: [UUID]) -> Int {
        let urls = resolved(ids).filter { $0.0.kind == .file }.map(\.1)
        if !urls.isEmpty { system.reveal(urls) }
        return urls.count
    }

    /// Copia rutas (archivos, también ausentes: última conocida) y URLs, una por línea.
    @discardableResult
    public func copyPaths(_ ids: [UUID]) -> Int {
        let set = Set(ids)
        let lines: [String] = items.filter { set.contains($0.id) }.compactMap {
            $0.kind == .web ? $0.webURL?.absoluteString : (url(for: $0)?.path ?? $0.lastKnownPath)
        }
        guard !lines.isEmpty else { return 0 }
        system.pasteboard.clearContents()
        system.pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        return lines.count
    }

    /// Elementos para `NSSharingServicePicker` (ver `ShelfSharing`).
    public func shareURLs(_ ids: [UUID]) -> [URL] { resolved(ids).map(\.1) }

    /// Quita de la shelf; el original no se toca.
    public func remove(_ ids: [UUID]) {
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
        for id in set { states[id] = nil; fileKeys[id] = nil }
        selection.subtract(set)
        persist()
    }

    public func clear() {
        items = []; states = [:]; fileKeys = [:]; selection = []; anchor = nil
        persist()
    }

    /// Mueve un elemento `offset` posiciones (AN-08).
    public func move(_ id: UUID, by offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + offset, 0), items.count - 1)
        guard j != i else { return }
        items.insert(items.remove(at: i), at: j)
        persist()
    }

    // MARK: - Arrastre (AN-06 / AN-07)

    public func dragEntered() { acceptedReset?.cancel(); dropState = .targeted }
    public func dragExited() { if dropState == .targeted { dropState = .idle } }

    private func flashAccepted(_ n: Int) {
        dropState = .accepted(count: n)
        acceptedReset?.cancel()
        acceptedReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            if case .accepted = self.dropState { self.dropState = .idle }
        }
    }

    // MARK: - Persistencia (opt-in)

    /// Activar: carga lo guardado (fuera del MainActor), lo fusiona con lo que haya en memoria y guarda.
    /// Hasta que la carga termina `isPersistent` sigue en false, para no pisar el fichero.
    /// Desactivar: borra el fichero (los elementos siguen en memoria, ahora temporales).
    public func setPersistence(_ on: Bool) {
        guard on != wantsPersistence else { return }
        wantsPersistence = on
        if on {
            let url = storageURL
            persistenceTask = Task { [weak self] in
                let loaded = await Task.detached { ShelfStorage.load(url) }.value
                self?.finishEnablingPersistence(loaded)
            }
        } else {
            isPersistent = false
            eraseFile()
        }
    }

    private func finishEnablingPersistence(_ loaded: (items: [ShelfItem], issue: ShelfLoadIssue?)) {
        guard wantsPersistence else { return }
        loadIssue = loaded.issue ?? loadIssue
        let memory = items
        var seen = Set(loaded.items.compactMap { key(of: $0) })
        let before = Set(loaded.items.map(\.id))
        items = loaded.items
        for m in memory where !before.contains(m.id) {
            if let k = key(of: m), !seen.insert(k).inserted { states[m.id] = nil; fileKeys[m.id] = nil; continue }
            items.append(m)
        }
        isPersistent = true
        trim()
        persist()
        refresh()
    }

    public func setHistoryLimit(_ n: Int) {
        historyLimit = min(max(n, 1), Self.maxHistoryLimit)
        trim(); persist()
    }

    /// Borrado completo: vacía la shelf y elimina el fichero (y su copia `.corrupt`).
    public func eraseAllData() {
        items = []; states = [:]; fileKeys = [:]; selection = []; anchor = nil; loadIssue = nil
        eraseFile()
    }

    /// Espera a que terminen las escrituras pendientes (pruebas y cierre de la app).
    public func flush() async {
        await persistenceTask?.value
        while let t = addTasks.values.first { await t.value }
        await refreshTask?.value
        await lastWrite?.value
    }

    private func trim() {
        guard isPersistent, items.count > historyLimit else { return }
        let drop = items.prefix(items.count - historyLimit).map(\.id)
        items.removeFirst(drop.count)
        for id in drop { states[id] = nil; fileKeys[id] = nil }
        selection.subtract(drop)
    }

    private func persist() {
        guard isPersistent, let data = ShelfStorage.encode(items.filter { !pendingIDs.contains($0.id) }) else { return }
        seq += 1
        let (s, url, w) = (seq, storageURL, writer)
        lastWrite = Task { [weak self] in
            let err = await w.write(data, to: url, seq: s)
            self?.writeError = err
        }
    }

    private func eraseFile() {
        seq += 1
        let (s, url, w) = (seq, storageURL, writer)
        lastWrite = Task { await w.erase(url, seq: s) }
    }

    // MARK: - Claves de duplicado

    /// Sin E/S: clave canónica si ya se calculó fuera del MainActor; si no, la última ruta conocida.
    private func key(of item: ShelfItem) -> String? {
        switch item.kind {
        case .web: return item.webURL.map { "web:" + $0.absoluteString }
        case .file: return fileKeys[item.id] ?? item.lastKnownPath.map { "file:" + $0 }
        }
    }

    private static func webName(_ u: URL) -> String {
        let host = u.host ?? u.absoluteString
        let path = u.path == "/" ? "" : u.path
        return host + path
    }
}
