import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppCoordinator(arguments: CommandLine.arguments)
        coordinator = c
        c.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        // Un volumen que no responde no debe impedir salir: si la E/S no termina en 2 s, se sale igualmente.
        var replied = false
        let reply = { @MainActor in
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in await coordinator.flushPersistence(); reply() }
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); reply() }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
}
