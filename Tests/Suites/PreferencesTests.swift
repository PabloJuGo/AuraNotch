import AuraCore
@testable import AuraPreferences
import AuraDesignSystem
import Foundation
import SwiftUI
import AppKit

private func freshDefaults() -> UserDefaults {
    let n = "aura.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
}

func runPreferencesSuite(_ t: SelfCheck) {
    MainActor.assumeIsolated { prefsChecks(t) }
}

@MainActor private func prefsChecks(_ t: SelfCheck) {
    // Ajustes ilegibles (p. ej. versión futura): se respaldan antes de que el flush los pise (auditoría #8).
    let bad = UserDefaults(suiteName: "aura.test.unreadable")!
    bad.removePersistentDomain(forName: "aura.test.unreadable")
    let junk = Data("{\"schemaVersion\": 999, \"x\": 1}".utf8)
    bad.set(junk, forKey: SettingsStore.key)
    let st = SettingsStore(defaults: bad)
    st.flush()
    t.expect(st.settings == AppSettings(), "ilegible -> valores por defecto")
    t.expect(bad.data(forKey: SettingsStore.backupKey) == junk, "el original ilegible se conserva en copia de seguridad")
    bad.removePersistentDomain(forName: "aura.test.unreadable")
    // Defaults seguros
    let s0 = AppSettings()
    t.expect(!s0.persistShelf && !s0.launchAtLogin, "defaults: shelf y login desactivados")
    t.expect(s0.enabledModules == NotchModule.allCases.filter { $0 != .clipboard }, "defaults: todos menos el portapapeles (opt-in)")

    // Round-trip por UserDefaults
    let d = freshDefaults()
    let a = SettingsStore(defaults: d, saveDelay: .milliseconds(10))
    a.settings.persistShelf = true; a.settings.hoverDelay = 0.4; a.setModule(.calendar, enabled: false)
    a.flush()
    let b = SettingsStore(defaults: d)
    t.expect(b.settings == a.settings && b.settings.persistShelf, "round-trip")

    // Coalescencia: muchos cambios -> una escritura
    let c = SettingsStore(defaults: freshDefaults(), saveDelay: .milliseconds(30))
    for i in 0..<20 { c.settings.historyLimit = i }
    t.expect(c.writeCount == 0, "coalescencia: nada escrito aún")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    t.expect(c.writeCount == 1, "coalescencia: una sola escritura (\(c.writeCount))")

    // Migración v0 -> v1
    let v0 = #"{"hover":false,"click":true,"hoverDelayMs":250,"startAtLogin":true,"persistShelf":true}"#
    let d0 = freshDefaults(); d0.set(Data(v0.utf8), forKey: SettingsStore.key)
    let m = SettingsStore(defaults: d0)
    t.expect(m.settings.schemaVersion == 1 && !m.settings.openOnHover && m.settings.hoverDelay == 0.25
             && m.settings.launchAtLogin && m.settings.persistShelf, "migración v0->v1")

    // Import inválido no pisa ajustes
    let before = a.settings
    for bad in ["basura", #"{"schemaVersion":99}"#, #"{"schemaVersion":1,"hoverDelay":50}"#, #"{"schemaVersion":1,"mode":"x"}"#] {
        var threw = false
        do { try a.importJSON(Data(bad.utf8)) } catch { threw = true }
        t.expect(threw && a.settings == before, "import rechazado: \(bad)")
    }
    // Export/import válido
    let out = try! b.exportJSON()
    let e = SettingsStore(defaults: freshDefaults())
    t.expect((try? e.importJSON(out)) != nil && e.settings == b.settings, "export/import")

    // Deshacer y reset
    e.settings.historyLimit = 7; e.settings.historyLimit = 9
    e.undo(); t.expect(e.settings.historyLimit == 7, "deshacer último cambio")
    e.resetToDefaults(); t.expect(e.settings == AppSettings(), "reset")
    e.undo(); t.expect(e.settings.historyLimit == 7, "reset es deshacible")

    // Apariencia: valores por defecto y ajustes antiguos (sin las claves nuevas) siguen cargando.
    t.expect(s0.accentTheme == .system && s0.compactTextWidth == .normal && s0.compactTextWidth.wing == 46, "apariencia: valores por defecto")
    t.expect(CompactTextWidth.narrow.wing < CompactTextWidth.normal.wing && CompactTextWidth.normal.wing < CompactTextWidth.wide.wing, "ancho del texto: estrecho < normal < ancho")
    if let data = try? JSONEncoder().encode(AppSettings()),
       var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        obj["accentTheme"] = nil; obj["compactTextWidth"] = nil
        if let old = try? JSONSerialization.data(withJSONObject: obj), let s = try? SettingsStore.decode(old) {
            t.expect(s.accentTheme == .system, "ajustes sin claves de apariencia: toman el valor por defecto")
        } else { t.expect(false, "ajustes sin claves de apariencia no cargan") }
    }

    // Idioma: inglés por defecto (también con ajustes antiguos), y se aplica a `AppleLanguages` antes de arrancar.
    t.expect(s0.language == .en, "idioma: inglés por defecto")
    let lang = freshDefaults()
    AppLanguage.applyStored(from: lang)
    t.expect(lang.stringArray(forKey: "AppleLanguages") == ["en"], "idioma: sin ajustes guardados -> inglés")
    var esSettings = AppSettings(); esSettings.language = .ptBR
    lang.set(try? JSONEncoder().encode(esSettings), forKey: SettingsStore.key)
    AppLanguage.applyStored(from: lang)
    t.expect(lang.stringArray(forKey: "AppleLanguages") == ["pt-BR"], "idioma: el guardado se aplica")
    lang.set(Data("{\"language\":\"xx\"}".utf8), forKey: SettingsStore.key)
    AppLanguage.applyStored(from: lang)
    t.expect(lang.stringArray(forKey: "AppleLanguages") == ["en"], "idioma: valor desconocido -> inglés")
    t.expect(AppLanguage.allCases.allSatisfy { !$0.nativeName.isEmpty }, "idioma: todos tienen nombre propio")

    // Orden de módulos sin duplicados ni perdidos
    let n = AppSettings.normalizedOrder([.shelf, .shelf, .home])
    t.expect(n.count == NotchModule.allCases.count && Set(n) == Set(NotchModule.allCases) && n.prefix(2) == [.shelf, .home], "orden normalizado")
    e.moveModules(from: IndexSet(integer: 4), to: 0)
    t.expect(e.settings.moduleOrder.first == .widgets && Set(e.settings.moduleOrder).count == NotchModule.allCases.count, "mover módulo")

    // Borrado completo
    var called = false
    a.onEraseAllData = { called = true }
    a.eraseAllData()
    t.expect(called && a.settings == AppSettings() && !a.canUndo && SettingsStore(defaults: d).settings == AppSettings(),
             "borrado completo")

    // LoginItem sin .app: no crashea
    if case .unavailable = LoginItem.state {} else { t.expect(false, "LoginItem fuera de .app debe ser unavailable") }
    t.expect(LoginItem.setEnabled(true) == LoginItem.state, "LoginItem.setEnabled no lanza")

    // Render a PNG
    if CommandLine.arguments.contains("--render-prefs") { renderPrefs() }
}

@MainActor private func renderPrefs() {
    let dir = ProcessInfo.processInfo.environment["AURA_RENDER_DIR"] ?? "/tmp/aura-renders"
    for (cat, name) in [(SettingsCategory.general, "general"), (.interaction, "interaction"), (.modules, "modules"), (.privacy, "privacy")] {
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: SettingsView(store: SettingsStore(defaults: freshDefaults()), initial: cat))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = host; win.appearance = host.appearance
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 480); host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { print("sin render \(name)"); continue }
            try? png.write(to: URL(fileURLWithPath: "\(dir)/prefs-\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
