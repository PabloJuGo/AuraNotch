import AppKit
import SwiftUI
import AuraCore
import AuraNotchSurface
import AuraPreferences
import AuraShelf
import AuraMedia
import AuraWidgets
import AuraCalendar
import AuraHome
import AuraClipboard
import AuraAlerts
import Observation

/// Arranque y ciclo de vida (§6.4). Argumentos de desarrollo:
/// `--selftest-window` verificación real de la ventana (sale con 0/1) · `--start-expanded` arranca abierta · `--start-module=<home|media|shelf|calendar|widgets>` · `--skip-onboarding` (capturas/pruebas).
@MainActor final class AppCoordinator {
    private let surface: SurfaceWindowController
    private let arguments: [String]
    private let store: SettingsStore
    private let settingsWindow: SettingsWindowController
    private let bridge = SurfaceBridge()
    private let shelf: ShelfService
    private let media = MediaService(providers: [MusicProvider(remembered: .standard), SpotifyProvider(remembered: .standard)])
    private let timer = TimerService()
    private let alerts = AlertCenter()
    private let clipboard = ClipboardService()
    private let battery = BatteryService()
    private let alertSources: AlertSources
    private let onboarding: OnboardingWindowController
    private let timerNotifier = SystemTimerNotifier() // TimerService.notifier es weak: hay que retenerlo aquí
    private let widgets: WidgetRegistry
    private let calendar: CalendarService
    private var statusItem: NSStatusItem?
    private var appliedModules: [NotchModule] = []
    private var isSelfTest: Bool { arguments.contains("--selftest-window") }

    init(arguments: [String]) {
        self.arguments = arguments
        // El autotest no debe tocar las preferencias reales del usuario.
        let selfTest = arguments.contains("--selftest-window")
        store = SettingsStore(defaults: selfTest ? (UserDefaults(suiteName: "aura.selftest") ?? .standard) : .standard)
        settingsWindow = SettingsWindowController(store: store)
        // El autotest no debe leer ni escribir el estado real del onboarding.
        onboarding = OnboardingWindowController(store: store, state: OnboardingState(defaults: selfTest ? (UserDefaults(suiteName: "aura.selftest") ?? .standard) : .standard))
        let bridge = bridge
        // En autotest la shelf es temporal en memoria: nunca toca el disco real.
        shelf = ShelfService(historyLimit: store.settings.historyLimit, persistent: !selfTest && store.settings.persistShelf)
        bridge.shelf = shelf
        store.onEraseAllData = { [shelf] in shelf.eraseAllData() }
        var config = SurfaceConfig()
        Self.apply(store.settings, to: &config)
        if selfTest { config.hotKey = nil; config.context.openOnHover = false }
        let ek = EventKitCalendar()
        calendar = CalendarService(authorizer: GuardedCalendarAuthorizer(base: ek), source: ek, opener: SystemCalendarOpener())
        widgets = WidgetRegistry(widgets: [timer, VolumeService(), battery, DateService(), QuickActionsService()],
                                 layout: Self.loadWidgetLayout(selfTest: selfTest))
        widgets.onLayoutChange = { layout in
            if !selfTest, let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: "aura.widgets.layout") }
        }
        alertSources = AlertSources(alerts: alerts, calendar: calendar, timer: timer)
        bridge.battery = battery
        bridge.alerts = alerts; bridge.clipboard = clipboard
        bridge.media = media; bridge.timer = timer; bridge.widgets = widgets; bridge.calendar = calendar
        bridge.modules = { [store] in store.settings.enabledModules }
        bridge.showCompactTitle = { [store] in store.settings.showCompactTitle }
        bridge.accent = { [store] in store.settings.accentTheme }
        surface = SurfaceWindowController(
            config: config,
            content: { model in AnyView(SurfaceRootView(model: model, bridge: bridge)) },
            fullscreenDetector: selfTest ? nil : SystemFullscreenDetector())
        bridge.surface = surface
        surface.modules = store.settings.enabledModules
        surface.onDrop = { [shelf] urls in _ = shelf.add(urls: urls) }
        // La superficie solo avisa con la multimedia en el compacto; aquí se respeta el ajuste. Anterior = dedos a la derecha.
        surface.onSwipe = { [store, media] dir in
            guard store.settings.swipeToSkip, media.compactInfo != nil else { return }
            Task { await media.skip(forward: dir == .next) }
        }
        // El panel flota por encima de todo: se pliega para que Ajustes no quede tapado.
        bridge.onOpenSettings = { [settingsWindow, weak surface] in settingsWindow.show(); surface?.send(.escape) }
    }

    func start() {
        timer.notifier = timerNotifier
        surface.start()
        if isSelfTest {
            Task { @MainActor [surface] in
                let ok = await WindowSelfTest(surface).run()
                surface.stop()
                exit(ok ? 0 : 1)
            }
            return
        }
        installStatusItem()
        if OnboardingState().shouldShow, !arguments.contains("--skip-onboarding") { onboarding.show() }
        observeSettings()
        applyModuleEnablement()
        observeActivity()
        alertSources.start()
        let module = arguments.compactMap { $0.hasPrefix("--start-module=") ? NotchModule(rawValue: String($0.dropFirst(15))) : nil }.first
        if arguments.contains("--start-expanded") || module != nil { surface.send(.hotkey) }
        if let module { surface.send(.selectModule(module)) }
    }

    func stop() { alertSources.stop(); store.flush(); surface.stop() }

    /// La escritura de la shelf es asíncrona: salir solo cuando haya terminado (evita perder el último cambio).
    func flushPersistence() async { await shelf.flush() }

    /// Ajustes → configuración del host. El atajo global solo se lee al arrancar (limitación conocida).
    private static func apply(_ s: AppSettings, to config: inout SurfaceConfig) {
        config.mode = s.mode
        config.showCompactTitle = s.showCompactTitle
        config.sizes.wing = CGFloat(s.compactTextWidth.wing)
        config.context.openOnClick = s.openOnClick
        config.context.openOnHover = s.openOnHover
        config.context.hoverDelay = s.hoverDelay
        config.context.fullscreenPolicy = s.fullscreen == .hide ? .hide : .keepVisible
        if !s.openOnHotKey { config.hotKey = nil }
    }

    private static func motion(_ o: MotionOverride) -> MotionPreference {
        switch o { case .system: .full; case .reduced: .reduced; case .none: .none }
    }

    private static func loadWidgetLayout(selfTest: Bool) -> WidgetLayout? {
        guard !selfTest, let data = UserDefaults.standard.data(forKey: "aura.widgets.layout") else { return nil }
        return try? JSONDecoder().decode(WidgetLayout.self, from: data)
    }

    /// Una sola actividad dominante en el compacto (§3.4): el temporizador gana a la multimedia.
    /// Solo reacciona a eventos (Observation): sin polling; el texto del temporizador lo refresca la vista.
    private func observeActivity() {
        withObservationTracking {
            _ = alerts.current
            _ = timer.phase
            _ = media.compactInfo
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.surface.send(.activityChanged(self.alerts.current != nil ? .alert : self.timer.compactInfo?.activity ?? self.media.compactInfo?.activity))
                self.observeActivity()
            }
        }
    }

    /// Servicios con coste (escuchar notificaciones, EventKit) solo corren si su módulo está activo.
    private func applyModuleEnablement() {
        appliedModules = store.settings.enabledModules
        let on = Set(appliedModules)
        if on.contains(.media) { media.start() } else { media.stop() }
        if on.contains(.calendar) { calendar.start() } else { calendar.stop() }
        if on.contains(.clipboard) { clipboard.start() } else { clipboard.stop() }
        alerts.enabled = store.settings.alertsEnabled
    }

    /// Re-aplica los ajustes al host cada vez que cambian (sin timers: Observation re-arma el seguimiento).
    private func observeSettings() {
        surface.motion.appPreference = Self.motion(store.settings.motionOverride)
        media.loadsRemoteArtwork = store.settings.loadSpotifyArtwork
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                var config = self.surface.config
                Self.apply(self.store.settings, to: &config)
                config.hotKey = self.surface.config.hotKey
                self.surface.config = config
                self.surface.context = config.context
                self.surface.modules = self.store.settings.enabledModules
                if self.store.settings.enabledModules != self.appliedModules { self.applyModuleEnablement() }
                self.alerts.enabled = self.store.settings.alertsEnabled
                self.shelf.setPersistence(self.store.settings.persistShelf)
                self.shelf.setHistoryLimit(self.store.settings.historyLimit)
                self.media.loadsRemoteArtwork = self.store.settings.loadSpotifyArtwork
                self.observeSettings()
            }
        }
    }

    /// Sin Dock ni menú, el icono de la barra es la forma de salir (y de alternar sin atajo).
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Aura Notch")
        let menu = NSMenu()
        let toggle = NSMenuItem(title: String(localized: "Alternar panel"), action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let prefs = NSMenuItem(title: String(localized: "Ajustes…"), action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(withTitle: String(localized: "Salir"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func toggle() { surface.send(.hotkey) }
}
