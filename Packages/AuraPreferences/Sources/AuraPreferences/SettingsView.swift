import SwiftUI
import AuraDesignSystem
import AuraCore

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General", interaction = "Interacción", animation = "Animaciones"
    case modules = "Módulos", privacy = "Privacidad", advanced = "Avanzado", about = "Acerca de"
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .general: String(localized: "General"); case .interaction: String(localized: "Interacción")
        case .animation: String(localized: "Animaciones"); case .modules: String(localized: "Módulos")
        case .privacy: String(localized: "Privacidad"); case .advanced: String(localized: "Avanzado")
        case .about: String(localized: "Acerca de")
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"; case .interaction: "cursorarrow.click"; case .animation: "sparkles"
        case .modules: "square.grid.2x2"; case .privacy: "hand.raised"; case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

/// Panel de ajustes nativo (§3.4): sidebar + Form agrupado, apariencia del sistema.
public struct SettingsView: View {
    @Bindable var store: SettingsStore
    @State private var selection: SettingsCategory
    @State private var loginMessage: String?
    @State private var confirmErase = false
    /// Idioma con el que arrancó esta sesión: si el elegido difiere, falta reiniciar.
    @State private var launchLanguage: AppLanguage

    public init(store: SettingsStore, initial: SettingsCategory = .general) {
        self.store = store
        _selection = State(initialValue: initial)
        _launchLanguage = State(initialValue: store.settings.language)
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { c in
                Label(c.title, systemImage: c.icon).tag(c)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detail.navigationTitle(selection.title)
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: general
        case .interaction: interaction
        case .animation: animation
        case .modules: modules
        case .privacy: privacy
        case .advanced: advanced
        case .about: about
        }
    }

    private func syncLoginMessage(_ s: LoginItem.State) {
        switch s {
        case .unavailable(let m): loginMessage = m
        case .requiresApproval: loginMessage = String(localized: "macOS necesita tu aprobación: Ajustes del Sistema > General > Ítems de inicio.")
        default: loginMessage = nil
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Abrir al iniciar sesión", isOn: $store.settings.launchAtLogin)
                    .accessibilityLabel("Abrir al iniciar sesión")
                    .onChange(of: store.settings.launchAtLogin) { _, on in
                        let now = LoginItem.state
                        if (on && now == .enabled) || (!on && now == .disabled) { return } // ya coincide: no re-registrar
                        syncLoginMessage(LoginItem.setEnabled(on))
                    }
                    .onAppear { // el usuario puede haberlo cambiado en Ajustes del Sistema
                        let now = LoginItem.state
                        syncLoginMessage(now)
                        if now == .enabled || now == .disabled { store.settings.launchAtLogin = (now == .enabled) }
                    }
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                Picker("Modo de pantalla", selection: $store.settings.mode) {
                    Text("Notch").tag(SurfaceMode.notch)
                    Text("Flotante superior centrado").tag(SurfaceMode.topCenterFloating)
                    Text("Desactivado en pantalla externa").tag(SurfaceMode.disabledOnExternalDisplay)
                }
                .accessibilityLabel("Modo de pantalla")
            }
            Section("Idioma") {
                Picker("Idioma de la interfaz", selection: $store.settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
                }
                .accessibilityLabel("Idioma de la interfaz")
                if store.settings.language != launchLanguage {
                    LabeledContent("Reinicia la app para aplicar el idioma.") {
                        Button("Reiniciar ahora") { AppRelaunch.relaunch(saving: store) }
                    }
                }
            }
            Section("Apariencia") {
                accentPicker
                Picker("Ancho del texto en el notch cerrado", selection: $store.settings.compactTextWidth) {
                    Text("Estrecho").tag(CompactTextWidth.narrow)
                    Text("Normal").tag(CompactTextWidth.normal)
                    Text("Ancho").tag(CompactTextWidth.wide)
                }
                .accessibilityLabel("Ancho del texto en el notch cerrado")
            }
        }.formStyle(.grouped)
    }

    /// Fila de muestras de color: una por tema, con el seleccionado marcado y nombre para VoiceOver.
    private var accentPicker: some View {
        LabeledContent("Color de acento") {
            HStack(spacing: 8) {
                ForEach(AccentTheme.allCases, id: \.self) { theme in
                    let selected = store.settings.accentTheme == theme
                    Button { store.settings.accentTheme = theme } label: {
                        Circle().fill(theme.color).frame(width: 18, height: 18)
                            .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                            .overlay { Circle().strokeBorder(.primary.opacity(selected ? 0.8 : 0.15), lineWidth: selected ? 2 : 1) }
                    }
                    .buttonStyle(.plain)
                    .help(theme.title)
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var interaction: some View {
        Form {
            Section("Activación") {
                Toggle("Abrir al pasar el puntero", isOn: $store.settings.openOnHover)
                    .accessibilityLabel("Abrir al pasar el puntero")
                Toggle("Abrir al hacer clic", isOn: $store.settings.openOnClick)
                    .accessibilityLabel("Abrir al hacer clic")
                Toggle("Abrir con atajo global (⌃⌥N)", isOn: $store.settings.openOnHotKey)
                    .accessibilityLabel("Abrir con atajo global (Control Opción N)")
                Text("El cambio del atajo global se aplica al reiniciar la app.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notch cerrado") {
                Toggle("Mostrar el título en el notch cerrado", isOn: $store.settings.showCompactTitle)
                    .accessibilityLabel("Mostrar el título en el notch cerrado")
                Toggle("Deslizar con dos dedos para cambiar de canción", isOn: $store.settings.swipeToSkip)
                    .accessibilityLabel("Deslizar con dos dedos para cambiar de canción")
                Text("Con la música visible en el notch cerrado, desliza horizontalmente: a la izquierda, la siguiente; a la derecha, la anterior.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Avisos en el notch (reunión, cargador, temporizador)", isOn: $store.settings.alertsEnabled)
                    .accessibilityLabel("Mostrar avisos en el notch")
            }
            Section("Retraso al pasar el puntero") {
                Slider(value: $store.settings.hoverDelay, in: AppSettings.hoverDelayRange, step: 0.02) {
                    Text("Retraso: \(Self.spokenSeconds(store.settings.hoverDelay))")
                } minimumValueLabel: { Text("0 s") } maximumValueLabel: { Text("1 s") }
                .disabled(!store.settings.openOnHover)
                .accessibilityLabel("Retraso al pasar el puntero")
                .accessibilityValue(Self.spokenSeconds(store.settings.hoverDelay))
            }
            Section("Pantalla completa") {
                Picker("En apps a pantalla completa", selection: $store.settings.fullscreen) {
                    Text("Ocultar").tag(FullscreenBehavior.hide)
                    Text("Mantener visible").tag(FullscreenBehavior.keepVisible)
                }
                .accessibilityLabel("En apps a pantalla completa")
                Text("Con «Ocultar», el panel se retira mientras otra app ocupa la pantalla completa.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var animation: some View {
        Form {
            Section {
                Slider(value: $store.settings.animationIntensity, in: 0...1) {
                    Text("Intensidad")
                } minimumValueLabel: { Text("Baja") } maximumValueLabel: { Text("Alta") }
                .accessibilityLabel("Intensidad de la animación")
                .accessibilityValue("\(Int((store.settings.animationIntensity * 100).rounded())) por ciento")
                .disabled(true) // sin efecto todavía: el host solo aplica «Movimiento»
                Text("La intensidad aún no se aplica; usa «Movimiento».").font(.caption).foregroundStyle(.secondary)
                Picker("Movimiento", selection: $store.settings.motionOverride) {
                    Text("Seguir al sistema").tag(MotionOverride.system)
                    Text("Reducido").tag(MotionOverride.reduced)
                    Text("Sin animaciones").tag(MotionOverride.none)
                }
                .accessibilityLabel("Movimiento")
            } footer: { Text("«Seguir al sistema» respeta Reducir movimiento de Accesibilidad.") }
        }.formStyle(.grouped)
    }

    private var modules: some View {
        Form {
            Section {
                List {
                    let order = AppSettings.normalizedOrder(store.settings.moduleOrder)
                    ForEach(Array(order.enumerated()), id: \.element) { i, m in
                        HStack {
                            Toggle(Self.name(m), isOn: Binding(
                                get: { !store.settings.disabledModules.contains(m) },
                                set: { store.setModule(m, enabled: $0) }))
                                .accessibilityLabel(Self.name(m))
                            Button { store.moveModules(from: IndexSet(integer: i), to: i - 1) } label: { Image(systemName: "chevron.up") }
                                .disabled(i == 0)
                                .accessibilityLabel("Subir \(Self.name(m))").help("Subir \(Self.name(m))")
                            Button { store.moveModules(from: IndexSet(integer: i), to: i + 2) } label: { Image(systemName: "chevron.down") }
                                .disabled(i == order.count - 1)
                                .accessibilityLabel("Bajar \(Self.name(m))").help("Bajar \(Self.name(m))")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: "Mover arriba") { if i > 0 { store.moveModules(from: IndexSet(integer: i), to: i - 1) } }
                        .accessibilityAction(named: "Mover abajo") { if i < order.count - 1 { store.moveModules(from: IndexSet(integer: i), to: i + 2) } }
                    }
                    .onMove { store.moveModules(from: $0, to: $1) }
                }
            } footer: { Text("Arrastra o usa Subir/Bajar para ordenar. Los módulos desactivados no se ejecutan.") }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section {
                Toggle("Conservar el shelf entre sesiones", isOn: $store.settings.persistShelf)
                    .accessibilityLabel("Conservar el shelf entre sesiones")
                // Dos botones en vez de Stepper: las flechas internas del Stepper de AppKit no tienen nombre accesible.
                let limit = store.settings.historyLimit, range = AppSettings.historyLimitRange
                HStack {
                    Text("Límite de historial: \(limit)")
                    Spacer()
                    Button { store.settings.historyLimit = max(range.lowerBound, limit - 10) } label: { Image(systemName: "minus") }
                        .disabled(limit <= range.lowerBound)
                        .accessibilityLabel("Reducir el límite de historial").help("Reducir el límite de historial")
                    Button { store.settings.historyLimit = min(range.upperBound, limit + 10) } label: { Image(systemName: "plus") }
                        .disabled(limit >= range.upperBound)
                        .accessibilityLabel("Aumentar el límite de historial").help("Aumentar el límite de historial")
                }
                .accessibilityElement(children: .contain)
                .accessibilityValue("\(limit) elementos")
                Toggle("Cargar la portada de Spotify", isOn: $store.settings.loadSpotifyArtwork)
                    .accessibilityLabel("Cargar la portada de Spotify")
                Text("Es lo único que usa la red: descarga solo la imagen de la portada desde la dirección que da Spotify.")
                    .font(.caption).foregroundStyle(.secondary)
            } footer: { Text("Aura Notch no usa analítica ni pide permisos por defecto; la única red es la portada de Spotify, que puedes desactivar. El shelf es temporal salvo que lo actives.") }
            Section {
                Button("Borrar todos los datos…", role: .destructive) { confirmErase = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("¿Borrar todos los datos y restablecer ajustes?", isPresented: $confirmErase) {
            Button("Borrar todo", role: .destructive) { store.eraseAllData() }
        } message: { Text("Esta acción no se puede deshacer.") }
    }

    private var advanced: some View {
        Form {
            Section("Ajustes") {
                Button("Deshacer último cambio") { store.undo() }.disabled(!store.canUndo)
                Button("Restablecer valores por defecto") { store.resetToDefaults() }
            }
            if let e = store.lastError { Section { Text(e).foregroundStyle(.red) } }
        }.formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                LabeledContent("Aura Notch", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "desarrollo"))
                Text("Sin telemetría. Licencia y créditos: ver el repositorio.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    /// «0,12 segundos» / «1 segundo» (con la coma decimal del idioma).
    static func spokenSeconds(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(0...2)))
        return v == 1 ? String(localized: "\(n) segundo") : String(localized: "\(n) segundos")
    }

    static func name(_ m: NotchModule) -> String {
        switch m {
        case .home: String(localized: "Inicio"); case .media: String(localized: "Multimedia"); case .shelf: String(localized: "Estantería")
        case .calendar: String(localized: "Calendario"); case .widgets: String(localized: "Widgets"); case .clipboard: String(localized: "Portapapeles")
        }
    }
}
