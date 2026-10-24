import AppKit
import AuraCore
import AuraShelf
import CryptoKit
import SwiftUI

/// Suite de AuraShelf (AURA-009/010). Ficheros temporales reales. Con `AURA_SHELF_RENDER_DIR=<ruta>`
/// además genera PNG (ImageRenderer, sin ventana) para revisión visual.
@MainActor
func runShelfSuite(_ t: SelfCheck) {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aura-shelf-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fx = ShelfFixture(dir: tmp)
    shelfAddAndDuplicates(t, fx)
    shelfMissingAndRecovery(t, fx)
    shelfActionsAndBatch(t, fx)
    shelfSelectionAndOrder(t, fx)
    shelfPersistence(t, fx)
    shelfSlowIONeverBlocksMain(t, fx)
    shelfDragOut(t, fx)
    shelfAirDrop(t, fx)
    if let dir = ProcessInfo.processInfo.environment["AURA_SHELF_RENDER_DIR"] { shelfRender(t, fx, to: dir) }
}

// MARK: - Utilidades

@MainActor
private final class ShelfFixture {
    let dir: URL
    var opened: [URL] = []
    var revealed: [URL] = []
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("aura.shelf.test.\(UUID().uuidString)"))

    init(dir: URL) { self.dir = dir }

    var io: ShelfIO = .live
    var system: ShelfSystem {
        ShelfSystem(open: { [unowned self] in opened.append($0); return true },
                    reveal: { [unowned self] in revealed += $0 }, pasteboard: pasteboard, io: io)
    }

    func file(_ name: String, _ text: String = "contenido") -> URL {
        let u = dir.appendingPathComponent(name)
        try? text.data(using: .utf8)!.write(to: u)
        return u
    }

    func service(_ name: String = "shelf.json", persistent: Bool = false, limit: Int = 50) -> ShelfService {
        let s = ShelfService(storageURL: dir.appendingPathComponent("store-\(name)"), historyLimit: limit,
                             persistent: persistent, system: system)
        if persistent { wait(s) }  // la carga ya no es síncrona
        return s
    }

    func storeURL(_ name: String = "shelf.json") -> URL { dir.appendingPathComponent("store-\(name)") }
}

private func sha(_ u: URL) -> String {
    guard let d = try? Data(contentsOf: u) else { return "∅" }
    return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}


/// Bombea el run loop hasta que `op` (async) termina; así el MainActor sigue libre como en la app.
@MainActor private func pumpUntilDone<T: Sendable>(_ limit: TimeInterval = 10, _ op: @MainActor @escaping () async -> T) -> T? {
    var out: T?
    var done = false
    Task { out = await op(); done = true }
    let end = Date().addingTimeInterval(limit)
    while !done && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    return out
}

@MainActor @discardableResult private func addNow(_ s: ShelfService, _ urls: [URL]) -> ShelfAddResult {
    pumpUntilDone { await s.addResolved(urls: urls) } ?? ShelfAddResult()
}
@MainActor private func refreshNow(_ s: ShelfService) { _ = pumpUntilDone { await s.refreshAndWait() } }
@MainActor private func recoverNow(_ s: ShelfService, _ id: UUID) -> Bool { pumpUntilDone { await s.recover(id) } ?? false }

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

// MARK: - E/S lenta fuera del MainActor (§6.5)

@MainActor private func shelfSlowIONeverBlocksMain(_ t: SelfCheck, _ fx: ShelfFixture) {
    let calls = Counter()
    let live = ShelfIO.live
    fx.io = ShelfIO(bookmark: { Thread.sleep(forTimeInterval: 1); return live.bookmark($0) },
                    key: live.key,
                    resolve: { calls.bump(); Thread.sleep(forTimeInterval: 2); return live.resolve($0) })
    defer { fx.io = .live }
    let s = fx.service("slow.json")
    let f = fx.file("lento.txt")

    // Alta: el elemento aparece ya (optimista) y el bookmark lento no bloquea el MainActor.
    let t0 = Date()
    s.add(urls: [f])
    t.expect(s.items.count == 1 && s.url(for: s.items[0]) != nil, "alta lenta: visible al instante, sin esperar a disco")
    t.expect(Date().timeIntervalSince(t0) < 0.5, "add(urls:) no bloquea (\(Date().timeIntervalSince(t0)) s)")
    var ticks = 0
    var done = false
    Task { await s.flush(); done = true }
    while !done && Date().timeIntervalSince(t0) < 10 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)); ticks += 1
    }
    t.expect(done && s.items.first?.bookmarkData != nil, "el bookmark se aplica al terminar")
    t.expect(ticks > 30, "MainActor sigue vivo durante el bookmark lento (\(ticks) vueltas)")

    // Dos lotes en vuelo con el mismo archivo: solo uno sobrevive.
    let g = fx.file("doble.txt")
    s.add(urls: [g]); s.add(urls: [g])
    wait(s)
    t.expect(s.items.filter { $0.name == "doble.txt" }.count == 1, "dos lotes en vuelo se deduplican")

    // Refresco lento: no bloquea y no apila.
    let before = calls.value
    let t1 = Date()
    s.refresh(); s.refresh(); s.refresh()
    t.expect(Date().timeIntervalSince(t1) < 0.5, "refresh() no bloquea")
    ticks = 0; done = false
    Task { await s.flush(); done = true }
    while !done && Date().timeIntervalSince(t1) < 15 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)); ticks += 1
    }
    t.expect(done && Date().timeIntervalSince(t1) >= 1.9, "la resolución lenta sí tardó ~2 s en segundo plano")
    t.expect(ticks > 100, "MainActor sigue vivo durante la resolución lenta (\(ticks) vueltas)")
    t.expect(calls.value - before == s.items.count, "3 refresh() = 1 pasada, sin apilar (\(calls.value - before) resoluciones)")
}

// MARK: - Alta y duplicados

@MainActor private func shelfAddAndDuplicates(_ t: SelfCheck, _ fx: ShelfFixture) {
    let s = fx.service()
    let a = fx.file("a.txt"), b = fx.file("sin-extension"), c = fx.file("raro.zzqq9")
    let long = fx.file(String(repeating: "n", count: 200) + ".txt")
    let folder = fx.dir.appendingPathComponent("carpeta")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let r = addNow(s, [a, b, c, long, folder, a])
    t.expect(r.added.count == 5, "5 añadidos (tipos desconocidos, nombre largo y carpeta OK), hubo \(r.added.count)")
    t.expect(r.duplicates.count == 1, "el repetido en el mismo lote es duplicado")
    t.expect(s.items.first?.kind == .file && s.items.first?.bookmarkData != nil, "archivo con bookmark")

    // Mismo recurso por otra ruta (symlink y /private): no se duplica.
    let link = fx.dir.appendingPathComponent("enlace.txt")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
    let r2 = addNow(s, [link, URL(fileURLWithPath: "/private" + a.path.replacingOccurrences(of: "/private", with: ""))])
    t.expect(r2.added.isEmpty && r2.duplicates.count == 2, "symlink / ruta alternativa = duplicado (\(r2.added.count) añadidos)")

    // Web y rechazos.
    let w = URL(string: "https://example.com/a/b")!
    t.expect(addNow(s, [w]).added.first?.kind == .web, "URL web admitida")
    t.expect(addNow(s, [w]).duplicates.count == 1, "URL web duplicada")
    let bad = addNow(s, [fx.dir.appendingPathComponent("no-existe"), URL(string: "ftp://x/y")!, URL(string: "javascript:alert(1)")!])
    t.expect(bad.rejected.count == 3 && bad.added.isEmpty, "inexistentes y esquemas no admitidos se rechazan")

    // Pasteboard de arrastre.
    let pb = NSPasteboard(name: NSPasteboard.Name("aura.shelf.drag.\(UUID().uuidString)"))
    pb.clearContents(); pb.writeObjects([fx.file("drag.txt") as NSURL])
    t.expect(s.add(pasteboard: pb).added.count == 1, "add(pasteboard:)")

    t.expect(s.dropState == .accepted(count: 1), "dropState tras alta: \(s.dropState)")
    s.dragEntered(); t.expect(s.dropState == .targeted, "dragEntered -> targeted")
    s.dragExited(); t.expect(s.dropState == .idle, "dragExited -> idle")
}

// MARK: - Ausente / movido / recuperación

@MainActor private func shelfMissingAndRecovery(_ t: SelfCheck, _ fx: ShelfFixture) {
    let s = fx.service()
    let moved = fx.file("mover.txt", "m"), gone = fx.file("borrar.txt", "b")
    addNow(s, [moved, gone])
    let movedID = s.items[0].id, goneID = s.items[1].id

    let newURL = fx.dir.appendingPathComponent("movido-renombrado.txt")
    try? FileManager.default.moveItem(at: moved, to: newURL)
    try? FileManager.default.removeItem(at: gone)
    refreshNow(s)
    if case .available(let u) = s.state(of: movedID) {
        t.expect(u.lastPathComponent == "movido-renombrado.txt", "el bookmark sigue al archivo movido/renombrado")
    } else { t.expect(false, "archivo movido debe seguir disponible vía bookmark") }
    t.expect(s.state(of: goneID) == .missing, "archivo borrado -> missing")
    t.expect(recoverNow(s, goneID) == false, "recuperar sin archivo sigue missing")
    t.expect(s.items[1].lastKnownPath?.hasSuffix("borrar.txt") == true, "se conserva la última ruta")

    // Papelera (carpeta .Trash) = ausente; al sacarlo de ahí, recover lo devuelve.
    let t1 = fx.file("papelera.txt", "p")
    addNow(s, [t1])
    let tid = s.items.last!.id
    let trash = fx.dir.appendingPathComponent(".Trash", isDirectory: true)
    try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    try? FileManager.default.moveItem(at: t1, to: trash.appendingPathComponent("papelera.txt"))
    refreshNow(s)
    t.expect(s.state(of: tid) == .missing, "en la Papelera = missing")
    try? FileManager.default.moveItem(at: trash.appendingPathComponent("papelera.txt"), to: t1)
    t.expect(recoverNow(s, tid) && s.state(of: tid) != .missing, "recover tras restaurar")
    s.remove([tid])

    s.remove([goneID])
    t.expect(s.items.count == 1 && s.states[goneID] == nil, "quitar elemento ausente")
}

// MARK: - Acciones y lote; originales intactos

@MainActor private func shelfActionsAndBatch(_ t: SelfCheck, _ fx: ShelfFixture) {
    let s = fx.service()
    let files = (1...3).map { fx.file("lote\($0).txt", "datos \($0)") }
    let before = files.map(sha)
    let times = files.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date }
    addNow(s, files + [URL(string: "https://example.com/x")!])
    let ids = s.items.map(\.id)

    t.expect(s.open(ids) == 4 && fx.opened.count == 4, "abrir lote (archivos y enlace)")
    t.expect(s.reveal(ids) == 3 && fx.revealed.count == 3, "revelar solo archivos")
    t.expect(s.copyPaths(ids) == 4, "copiar rutas lote")
    let text = fx.pasteboard.string(forType: .string) ?? ""
    t.expect(text.split(separator: "\n").count == 4 && text.contains("lote2.txt") && text.contains("https://example.com/x"), "pasteboard con rutas y URL")
    t.expect(s.shareURLs(ids).count == 4, "shareURLs")
    s.remove([ids[0]]); t.expect(s.items.count == 3, "quitar uno")
    s.clear(); t.expect(s.items.isEmpty && s.selection.isEmpty, "limpiar")

    t.expect(files.map(sha) == before, "originales con el mismo hash tras todas las acciones")
    let after = files.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date }
    t.expect(times == after, "originales con la misma fecha de modificación")
    t.expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "originales siguen en su sitio")
}

// MARK: - Selección y orden

@MainActor private func shelfSelectionAndOrder(_ t: SelfCheck, _ fx: ShelfFixture) {
    let s = fx.service()
    addNow(s, (1...5).map { fx.file("sel\($0).txt") })
    let ids = s.items.map(\.id)
    s.select(ids[1]); t.expect(s.selection == [ids[1]], "selección simple")
    s.select(ids[3], extend: true); t.expect(s.selection == [ids[1], ids[3]], "añadir con cmd")
    s.select(ids[3], extend: true); t.expect(s.selection == [ids[1]], "quitar con cmd")
    s.select(ids[1]); s.select(ids[3], range: true); t.expect(s.selection == Set(ids[1...3]), "rango con shift")
    t.expect(s.ids(forContextOf: ids[2]) == Array(ids[1...3]), "contexto sobre selección = lote")
    t.expect(s.ids(forContextOf: ids[0]) == [ids[0]], "contexto fuera de selección = solo ese")
    s.selectAll(); t.expect(s.selection.count == 5, "seleccionar todo")
    s.move(ids[0], by: 2); t.expect(s.items.map(\.id) == [ids[1], ids[2], ids[0], ids[3], ids[4]], "mover")
    s.move(ids[4], by: 10); t.expect(s.items.last?.id == ids[4], "mover se acota")
}

// MARK: - Persistencia

@MainActor private func shelfPersistence(_ t: SelfCheck, _ fx: ShelfFixture) {
    // Por defecto temporal: no escribe nada.
    let temp = fx.service("temp.json")
    addNow(temp, [fx.file("p0.txt")])
    t.expect(!temp.isPersistent && !FileManager.default.fileExists(atPath: fx.storeURL("temp.json").path), "por defecto no persiste")

    // Ida y vuelta.
    let p1 = fx.service("rt.json", persistent: true)
    let f1 = fx.file("rt1.txt"), f2 = fx.file("rt2.txt")
    addNow(p1, [f1, f2, URL(string: "https://example.com/rt")!])
    wait(p1)
    let p2 = fx.service("rt.json", persistent: true)
    t.expect(p2.items.map(\.name) == p1.items.map(\.name) && p2.items.count == 3, "ida y vuelta: \(p2.items.map(\.name))")
    t.expect(p2.items.allSatisfy { p2.state(of: $0.id) != .missing }, "referencias resueltas tras recargar")
    t.expect(p2.loadIssue == nil, "sin aviso")
    let mode = (try? FileManager.default.attributesOfItem(atPath: fx.storeURL("rt.json").path)[.posixPermissions]) as? Int
    t.expect(mode == 0o600, "fichero 0600 (\(String(describing: mode)))")

    // Fichero corrupto: arranca vacío, avisa, conserva copia, no crashea.
    try? Data("{no es json".utf8).write(to: fx.storeURL("bad.json"))
    let bad = fx.service("bad.json", persistent: true)
    t.expect(bad.items.isEmpty && bad.loadIssue == .corrupt, "corrupto -> vacío + aviso")
    t.expect(FileManager.default.fileExists(atPath: fx.storeURL("bad.json").appendingPathExtension("corrupt").path), "copia .corrupt conservada")
    addNow(bad, [fx.file("tras-corrupto.txt")]); wait(bad)
    t.expect(fx.service("bad.json", persistent: true).items.count == 1, "tras corrupto se puede volver a guardar")

    // Esquema futuro: no se pisa.
    try? Data(#"{"schemaVersion":99,"items":[]}"#.utf8).write(to: fx.storeURL("new.json"))
    let newer = fx.service("new.json", persistent: true)
    t.expect(newer.loadIssue == .newerSchema(99) && newer.items.isEmpty, "esquema futuro -> aviso")

    // Límite de historial: se queda con los más nuevos.
    let lim = fx.service("lim.json", persistent: true, limit: 3)
    addNow(lim, (1...6).map { fx.file("h\($0).txt") }); wait(lim)
    t.expect(lim.items.map(\.name) == ["h4.txt", "h5.txt", "h6.txt"], "límite 3: \(lim.items.map(\.name))")
    lim.setHistoryLimit(2); wait(lim)
    t.expect(fx.service("lim.json", persistent: true).items.count == 2, "límite reconfigurado se persiste")
    t.expect(ShelfService(storageURL: fx.storeURL("c"), historyLimit: 99999).historyLimit == ShelfService.maxHistoryLimit, "límite acotado")

    // Activar opt-in con elementos en memoria: se conservan; desactivar borra el fichero.
    let late = fx.service("late.json")
    addNow(late, [fx.file("late.txt")])
    late.setPersistence(true); wait(late)
    t.expect(fx.service("late.json", persistent: true).items.count == 1, "activar persistencia guarda lo existente")
    late.setPersistence(false); wait(late)
    t.expect(!FileManager.default.fileExists(atPath: fx.storeURL("late.json").path) && late.items.count == 1, "desactivar borra fichero, mantiene memoria")

    // Borrado completo (incluye .corrupt).
    bad.eraseAllData(); wait(bad)
    t.expect(bad.items.isEmpty && !FileManager.default.fileExists(atPath: fx.storeURL("bad.json").path)
             && !FileManager.default.fileExists(atPath: fx.storeURL("bad.json").appendingPathExtension("corrupt").path), "borrado completo de datos")

    // Escrituras rápidas: gana la última.
    let burst = fx.service("burst.json", persistent: true)
    for i in 1...20 { addNow(burst, [fx.file("b\(i).txt")]) }
    wait(burst)
    t.expect(fx.service("burst.json", persistent: true).items.count == 20, "ráfaga de escrituras: estado final correcto")
    t.expect(burst.writeError == nil, "sin error de escritura")
}

/// Espera a las escrituras (el runner es síncrono): bombea el run loop hasta que `flush` termina.
@MainActor private func wait(_ s: ShelfService) {
    var done = false
    Task { await s.flush(); done = true }
    let end = Date().addingTimeInterval(5)
    while !done && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

// MARK: - Render

@MainActor private func shelfRender(_ t: SelfCheck, _ fx: ShelfFixture, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func render(_ name: String, _ s: ShelfService, targeted: Bool = false) {
        if targeted { s.dragEntered() }
        let v = ShelfView(service: s).frame(width: 520, height: 190).background(Color.black)
            .environment(\.colorScheme, .dark)
        // ImageRenderer no rasteriza vistas con soporte AppKit (dropDestination): se usa NSHostingView.
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 190)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = host; win.appearance = NSAppearance(named: .darkAqua)
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { t.expect(false, "sin bitmap: \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { t.expect(false, "sin PNG: \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    render("shelf-empty", fx.service("r0"))

    let busy = fx.service("r1")
    let docs = ["Informe trimestral.pdf", "foto.png", "Nombre de archivo extremadamente largo que no cabe en la tarjeta.txt", "notas"].map { fx.file($0) }
    addNow(busy, docs + [URL(string: "https://example.com/articulo")!])
    busy.select(busy.items[1].id); busy.select(busy.items[3].id, extend: true)
    render("shelf-busy", busy)
    render("shelf-drop-targeted", busy, targeted: true)

    let missing = fx.service("r2")
    let gone = fx.file("desaparece.pdf")
    addNow(missing, [gone, fx.file("sigue-aqui.txt")])
    try? FileManager.default.removeItem(at: gone)
    refreshNow(missing)
    render("shelf-missing", missing)
}

// MARK: - Arrastre de salida (solo copia)

@MainActor private func shelfDragOut(_ t: SelfCheck, _ fx: ShelfFixture) {
    t.expect(ShelfDragOut.operationMask == .copy && !ShelfDragOut.operationMask.contains(.move)
             && !ShelfDragOut.operationMask.contains(.generic), "arrastre de salida: máscara solo .copy")
    let s = fx.service("drag.json")
    let a = fx.file("da.txt"), b = fx.file("db.txt"), gone = fx.file("dc.txt")
    addNow(s, [a, b, gone]); refreshNow(s)
    try? FileManager.default.removeItem(at: gone); refreshNow(s)
    let ids = s.items.map(\.id)
    let urls = ShelfDragOut.writers(for: ids, in: s).compactMap { ($0 as? NSURL) as URL? }
    t.expect(urls.map(\.lastPathComponent) == ["da.txt", "db.txt"], "arrastre: N seleccionadas en orden, sin las ausentes: \(urls.map(\.lastPathComponent))")
    t.expect(ShelfDragOut.writers(for: [ids[2]], in: s).isEmpty, "arrastre: solo ausentes = nada que arrastrar")
}

// MARK: - AirDrop (doble: no se abre el selector real)

@MainActor private final class FakeAirDrop: ShelfAirDropService {
    weak var delegate: NSSharingServiceDelegate?  // débil, como en NSSharingService
    var allowed = true
    var performed: [[Any]] = []
    func canPerform(withItems items: [Any]?) -> Bool { allowed }
    func perform(withItems items: [Any]) { performed.append(items) }
}

@MainActor private func shelfAirDrop(_ t: SelfCheck, _ fx: ShelfFixture) {
    let original = ShelfAirDrop.makeService
    defer { ShelfAirDrop.makeService = original }
    let fake = FakeAirDrop()
    ShelfAirDrop.makeService = { fake }
    let s = fx.service("airdrop.json")
    addNow(s, [fx.file("ad1.txt"), fx.file("ad2.txt")])
    let urls = s.shareURLs(s.items.map(\.id))

    t.expect(ShelfAirDrop.isAvailable(urls), "airdrop: disponible")
    t.expect(!ShelfAirDrop.send([]) && fake.performed.isEmpty, "airdrop: sin elementos no hace nada")
    t.expect(ShelfAirDrop.send(urls) && fake.performed.count == 1 && fake.performed[0].count == 2, "airdrop: envía el lote con un solo perform")
    t.expect(fake.delegate != nil, "airdrop: el delegado sigue vivo durante la operación")
    weak var weakDelegate = fake.delegate
    fake.delegate?.sharingService?(NSSharingService(named: .composeMessage)!, didShareItems: urls)
    t.expect(weakDelegate == nil, "airdrop: el delegado se libera al terminar")

    fake.allowed = false
    t.expect(!ShelfAirDrop.isAvailable(urls) && !ShelfAirDrop.send(urls) && fake.performed.count == 1,
             "airdrop: no disponible = no se abre el selector")
    ShelfAirDrop.makeService = { nil }
    t.expect(!ShelfAirDrop.isAvailable(urls) && !ShelfAirDrop.send(urls), "airdrop: sin servicio")
}
