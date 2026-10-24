import AppKit
import AuraPreferences

// El idioma elegido en Ajustes (inglés por defecto) debe fijarse antes de crear NSApplication.
AppLanguage.applyStored()

// App "accessory": sin Dock ni ventana principal; la única ventana es el panel de la superficie.
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
