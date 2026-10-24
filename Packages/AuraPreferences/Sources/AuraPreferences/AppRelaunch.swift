import AppKit

/// Reinicia la app (p. ej. tras cambiar de idioma). Solo tiene sentido con la app empaquetada.
@MainActor public enum AppRelaunch {
    public static func relaunch(saving store: SettingsStore) {
        store.flush()
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { NSApp.terminate(nil); return }
        // El proceso hijo espera a que esta instancia termine para que `open` no reutilice la que se está cerrando.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
