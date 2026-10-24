import AppKit
import AuraCore
import AuraDesignSystem
import SwiftUI

/// UI-06. Estados: loading, sin reproductor, error, ready. Solo muestra controles con capacidad declarada.
/// El progreso se interpola con TimelineView únicamente mientras reproduce y la vista está visible.
public struct MediaView: View {
    let service: MediaService
    @State private var visible = false
    @Environment(\.auraPanelOpen) private var panelOpen
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(service: MediaService) { self.service = service }

    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    public var body: some View {
        content
            .padding(Space.sm)
            .animation(Motion.animation(.switchModule, motion), value: service.state)
            .onAppear { visible = true }
            .task { await service.refreshAuthorization() }
            .onDisappear { visible = false }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MediaStrings.group)
    }

    @ViewBuilder private var content: some View {
        switch service.state {
        case .loading:
            VStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text(MediaStrings.loading).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .noPlayer:
            EmptyStateView(symbol: "music.note", title: MediaStrings.noPlayerTitle, message: MediaStrings.noPlayerMessage)
        case .error(let message):
            ErrorStateView(title: MediaStrings.errorTitle, cause: message, solution: MediaStrings.errorSolution,
                           onRetry: { service.start() })
        case .ready:
            if let snap = service.current { ready(snap) }
        }
    }

    private func ready(_ snap: MediaSnapshot) -> some View {
        let item = snap.item
        let controls = MediaControls(snap.capabilities, isPlaying: item.isPlaying)
        _ = service.positionEpoch  // dependencia observable: un seek externo redibuja el progreso
        return HStack(alignment: .center, spacing: Space.md) {
            artwork(item)
            VStack(alignment: .leading, spacing: Space.xs) {
                header(snap)
                Text(item.title).font(AuraFont.moduleTitle).foregroundStyle(AuraColor.primaryText.color).lineLimit(1)
                if let artist = item.artist {
                    Text(artist).font(AuraFont.body).foregroundStyle(AuraColor.secondaryText.color).lineLimit(1)
                }
                progress(item, seekable: controls.seek)
                transport(controls, isPlaying: item.isPlaying)
                authSection(snap)
                if let err = service.actionError {
                    Text(err).font(AuraFont.secondary).foregroundStyle(AuraColor.warning.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity) // centrado en el alto del panel
        .accessibilityElement(children: .contain)
    }

    private func header(_ snap: MediaSnapshot) -> some View {
        HStack(spacing: Space.xs) {
            Text(MediaStrings.sourceName(snap.providerID)).font(AuraFont.secondary)
                .foregroundStyle(AuraColor.secondaryText.color)
            if service.sources.count > 1 {
                Menu {
                    ForEach(service.sources, id: \.self) { id in
                        Button(MediaStrings.sourceName(id)) { service.selectSource(id) }
                    }
                } label: { Image(systemName: "chevron.up.chevron.down").font(AuraFont.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(MediaStrings.source)
            }
        }
    }

    private func artwork(_ item: MediaItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let image = item.artworkData.flatMap(NSImage.init(data:))
        return Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.title).foregroundStyle(AuraColor.secondaryText.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AuraColor.elevatedSurface.color)
            }
        }
        .frame(width: 72, height: 72).clipShape(shape)
        .shadow(color: .black.opacity(image == nil ? 0 : 0.3), radius: 5, y: 2)
        .animation(Motion.animation(.switchModule, motion), value: image != nil)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func progress(_ item: MediaItem, seekable: Bool) -> some View {
        if let duration = item.duration, duration > 0, service.position(at: Date()) != nil {
            TimelineView(.animation(minimumInterval: 1, paused: !(item.isPlaying && visible && panelOpen))) { ctx in
                let pos = service.position(at: ctx.date) ?? 0
                ProgressBar(position: pos, duration: duration)
                    .accessibilityRepresentation {
                        ProgressView(value: min(pos, duration), total: duration)
                            .accessibilityLabel(MediaStrings.progress)
                            .accessibilityValue(MediaStrings.progressValue(MediaFormat.time(pos), MediaFormat.time(duration)))
                            .accessibilityAddTraits(.updatesFrequently)
                            .accessibilityAdjustableAction { dir in
                                guard seekable else { return }
                                let delta: TimeInterval = dir == .increment ? 10 : -10
                                Task { await service.seek(by: delta) }
                            }
                    }
            }
        }
    }

    /// Transporte al estilo Reproduciendo ahora de macOS: glifos sin marco, play/pausa más grande, centrados.
    @ViewBuilder private func transport(_ c: MediaControls, isPlaying: Bool) -> some View {
        if c.previous || c.playPause || c.next || c.open {
            HStack(spacing: Space.md) {
                if c.previous { iconButton("backward.fill", MediaStrings.previous, size: 16) { await service.skip(forward: false) } }
                if c.playPause {
                    iconButton(isPlaying ? "pause.fill" : "play.fill", isPlaying ? MediaStrings.pause : MediaStrings.play, size: 22) {
                        await service.togglePlayPause()
                    }
                }
                if c.next { iconButton("forward.fill", MediaStrings.next, size: 16) { await service.skip(forward: true) } }
                if c.open { iconButton("arrow.up.forward.app", MediaStrings.open, size: 13, secondary: true) { await service.openSource() } }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, size: CGFloat, secondary: Bool = false,
                            _ action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: { Image(systemName: symbol).font(.system(size: size, weight: .semibold)) }
            .buttonStyle(TransportButtonStyle(secondary: secondary))
            .accessibilityLabel(label)
            .help(label)
    }

    /// Sin permiso de control: explicación + botón. El diálogo solo se dispara al pulsar.
    @ViewBuilder private func authSection(_ snap: MediaSnapshot) -> some View {
        if !snap.capabilities.contains(.play) {
            switch snap.authorization {
            case .notDetermined:
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(MediaStrings.authExplanation).font(AuraFont.secondary)
                        .foregroundStyle(AuraColor.secondaryText.color).fixedSize(horizontal: false, vertical: true)
                    Button(MediaStrings.allowControl) { Task { await service.requestAuthorization() } }
                        .buttonStyle(AuraButtonStyle(emphasis: .filled))
                }
            case .denied:
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(MediaStrings.authDenied).font(AuraFont.secondary)
                        .foregroundStyle(AuraColor.secondaryText.color).fixedSize(horizontal: false, vertical: true)
                    Button(Strings.openSettings) { Self.openAutomationSettings() }
                        .buttonStyle(AuraButtonStyle(emphasis: .filled))
                }
            default: EmptyView()
            }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Botón de transporte: sin fondo en reposo, disco tenue al pasar el ratón, se hunde al pulsar (como los de macOS).
public struct TransportButtonStyle: ButtonStyle {
    public init(secondary: Bool = false) { self.secondary = secondary }
    var secondary = false
    public func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, secondary: secondary) }

    private struct Styled: View {
        let configuration: ButtonStyle.Configuration
        let secondary: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle((secondary && !hovering ? AuraColor.secondaryText : AuraColor.primaryText).color)
                .frame(minWidth: 32, minHeight: 32)
                .background(Circle().fill(AuraColor.primaryText.color.opacity(configuration.isPressed ? 0.22 : hovering ? 0.12 : 0)))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

enum MediaFormat {
    static func time(_ t: TimeInterval) -> String {
        let s = Int(max(0, t)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ProgressBar: View {
    let position: TimeInterval, duration: TimeInterval
    var body: some View {
        HStack(spacing: Space.sm) {
            Text(MediaFormat.time(position)).font(AuraFont.numeric).foregroundStyle(AuraColor.secondaryText.color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AuraColor.separator.color)
                    Capsule().fill(AuraColor.primaryText.color)
                        .frame(width: geo.size.width * min(max(position / duration, 0), 1))
                }
            }
            .frame(height: 4)
            Text(MediaFormat.time(duration)).font(AuraFont.numeric).foregroundStyle(AuraColor.secondaryText.color)
        }
    }
}
