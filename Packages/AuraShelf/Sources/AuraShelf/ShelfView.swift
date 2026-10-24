import AppKit
import AuraCore
import AuraDesignSystem
import SwiftUI

/// UI-07. Estados: vacío, ocupado, archivo ausente. Sin previews de contenido (§5.2): solo el icono
/// de tipo que da `NSWorkspace.icon(forFile:)`. Sin animación permanente.
public struct ShelfView: View {
    let service: ShelfService
    @State private var shareURLs: [URL] = []
    @State private var airDropURLs: [URL] = []
    @State private var airDropTargeted = false
    @State private var airDropFailed = false
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(service: ShelfService) { self.service = service }

    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }
    private var targeted: Bool { service.dropState == .targeted }

    public var body: some View {
        VStack(spacing: Space.sm) {
            if let issue = service.loadIssue { banner(issue) }
            if service.items.isEmpty {
                EmptyStateView(symbol: "tray", title: ShelfStrings.emptyTitle, message: ShelfStrings.emptyMessage)
                addButton
                airDropZone
            } else {
                toolbar
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Space.sm) {
                        ForEach(service.items) { item in
                            ShelfCard(service: service, item: item, share: { shareURLs = $0 }, airDrop: sendAirDrop)
                                .transition(Motion.contentTransition(motion))
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .scrollIndicators(.hidden)
                .animation(Motion.animation(.dropAccepted, motion), value: service.items.count)
                .animation(Motion.animation(.reorder, motion), value: service.items.map(\.id))
                airDropZone
            }
        }
        .padding(Space.sm)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(AuraColor.accent.color, lineWidth: 2)
                .opacity(targeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .scaleEffect(targeted ? 1.01 : 1)
        .animation(Motion.animation(.dragOverShelf, motion), value: targeted)
        .overlay(alignment: .bottom) { acceptedBadge }
        .dropDestination(for: URL.self, action: { urls, _ in
            service.add(urls: urls)
            return !urls.isEmpty
        }, isTargeted: { $0 ? service.dragEntered() : service.dragExited() })
        .background { if !shareURLs.isEmpty { ShareAnchor(urls: $shareURLs) } }  // montado solo al compartir
        .background { if !airDropURLs.isEmpty { ShareAnchor(urls: $airDropURLs, airDrop: true) } }
        .task { service.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ShelfStrings.group)
        .accessibilityAction(named: ShelfStrings.add, chooseFiles)
        .accessibilityAction(named: ShelfStrings.airDropSend) { sendAirDrop(service.shareURLs(selectedIDs)) }
    }

    private var selectedIDs: [UUID] { service.items.map(\.id).filter(service.selection.contains) }

    private func sendAirDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard ShelfAirDrop.isAvailable(urls) else { airDropFailed = true; return }
        airDropFailed = false
        airDropURLs = urls
    }

    /// Zona de soltado: archivos de la shelf o de fuera abren el selector de AirDrop (sin añadirlos a la shelf).
    /// También es un botón (teclado/VoiceOver) que envía la selección.
    private var airDropZone: some View {
        let ids = selectedIDs
        let noService = !ShelfAirDrop.isAvailable(service.shareURLs(ids))
        let unavailable = airDropFailed || noService
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Button { sendAirDrop(service.shareURLs(ids)) } label: {
            Label(unavailable ? ShelfStrings.airDropUnavailable : airDropTargeted ? ShelfStrings.airDropDrop : ShelfStrings.airDrop,
                  systemImage: "airplayaudio")
                .font(AuraFont.secondary)
                .foregroundStyle(unavailable ? AuraColor.warning.color : AuraColor.secondaryText.color)
                .frame(maxWidth: .infinity).padding(.vertical, Space.xs)
                .overlay { shape.strokeBorder(airDropTargeted ? AuraColor.accent.color : AuraColor.secondaryText.color.opacity(0.4),
                                              style: StrokeStyle(lineWidth: airDropTargeted ? 2 : 1, dash: [4, 3])) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(noService)
        .dropDestination(for: URL.self, action: { urls, _ in
            sendAirDrop(urls)
            return !urls.isEmpty
        }, isTargeted: { airDropTargeted = $0; if $0 { airDropFailed = false } })
        .help(ShelfStrings.airDropHint)
        .accessibilityLabel(ShelfStrings.airDrop)
        .accessibilityHint(ids.isEmpty ? ShelfStrings.airDropHint : ShelfStrings.airDropSelectionHint)
    }

    /// Alternativa al arrastre (teclado/VoiceOver): panel de apertura, sin permisos nuevos.
    private var addButton: some View {
        Button(action: chooseFiles) { Label(ShelfStrings.add, systemImage: "plus") }
            .buttonStyle(AuraButtonStyle())
            .help(ShelfStrings.add)
            .accessibilityLabel(ShelfStrings.add)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = ShelfStrings.addPrompt
        panel.begin { [service] r in
            guard r == .OK else { return }
            Task { @MainActor in service.add(urls: panel.urls) }
        }
    }

    @ViewBuilder private var acceptedBadge: some View {
        if case .accepted(let n) = service.dropState {
            Label(ShelfStrings.accepted(n), systemImage: "checkmark")
                .font(AuraFont.compact).foregroundStyle(AuraColor.success.color)
                .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
                .background(Capsule().fill(AuraColor.elevatedSurface.color))
                .transition(.opacity)
        }
    }

    private func banner(_ issue: ShelfLoadIssue) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(AuraColor.warning.color)
                .accessibilityHidden(true)
            Text(issue == .corrupt ? ShelfStrings.loadCorrupt : ShelfStrings.loadNewer)
                .font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            Spacer(minLength: 0)
            Button(ShelfStrings.dismiss) { service.loadIssue = nil }.buttonStyle(AuraButtonStyle())
        }
    }

    private var toolbar: some View {
        let ids = service.items.map(\.id).filter(service.selection.contains)
        let some = !ids.isEmpty
        return HStack(spacing: Space.xs) {
            Text(some ? ShelfStrings.selectedCount(ids.count) : ShelfStrings.count(service.items.count))
                .font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            Spacer(minLength: 0)
            addButton
            iconButton("arrow.up.forward.app", ShelfStrings.open, enabled: some) { service.open(ids) }
            iconButton("folder", ShelfStrings.reveal, enabled: some) { service.reveal(ids) }
            iconButton("doc.on.doc", ShelfStrings.copyPath, enabled: some) { service.copyPaths(ids) }
            iconButton("square.and.arrow.up", ShelfStrings.share, enabled: some) { shareURLs = service.shareURLs(ids) }
            iconButton("dot.radiowaves.left.and.right", ShelfStrings.airDropSend,
                       enabled: some && ShelfAirDrop.isAvailable(service.shareURLs(ids))) { sendAirDrop(service.shareURLs(ids)) }
            iconButton("xmark", ShelfStrings.remove, enabled: some) { service.remove(ids) }
            iconButton("trash.slash", ShelfStrings.clear, enabled: true) { service.clear() }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { action() } label: { Image(systemName: symbol) }
            .buttonStyle(AuraButtonStyle())
            .disabled(!enabled)
            .help(label)
            .accessibilityLabel(label)
    }
}

/// Tarjeta de un elemento. Vista de su estado; las acciones delegan en el servicio.
struct ShelfCard: View {
    let service: ShelfService
    let item: ShelfItem
    let share: ([URL]) -> Void
    let airDrop: ([URL]) -> Void
    @FocusState private var focused: Bool

    private var state: ShelfItemState { service.state(of: item.id) }
    private var isMissing: Bool { state == .missing }
    private var isSelected: Bool { service.selection.contains(item.id) }
    private var targets: [UUID] { service.ids(forContextOf: item.id) }

    var body: some View {
        card
            .contextMenu { menu }
            .accessibilityElement(children: isMissing ? .contain : .ignore)
            .accessibilityLabel(isMissing ? "\(item.name), \(ShelfStrings.missing)" : item.name)
            .accessibilityHint(isMissing ? ShelfStrings.missingHint : ShelfStrings.removeHint)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: ShelfStrings.open) { service.open(targets) }
            .accessibilityAction(named: ShelfStrings.reveal) { service.reveal(targets) }
            .accessibilityAction(named: item.kind == .web ? ShelfStrings.copyLink : ShelfStrings.copyPath) { service.copyPaths(targets) }
            .accessibilityAction(named: ShelfStrings.share) { share(service.shareURLs(targets)) }
            .accessibilityAction(named: ShelfStrings.airDropSend) { airDrop(service.shareURLs(targets)) }
            .accessibilityAction(named: ShelfStrings.moveEarlier) { service.move(item.id, by: -1) }
            .accessibilityAction(named: ShelfStrings.moveLater) { service.move(item.id, by: 1) }
            .accessibilityAction(named: ShelfStrings.remove) { service.remove(targets) }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return VStack(spacing: Space.xs) {
            VStack(spacing: Space.xs) {
                icon.frame(width: 40, height: 40)
                Text(item.name).font(AuraFont.secondary).lineLimit(2).truncationMode(.middle)
                    .multilineTextAlignment(.center).foregroundStyle(AuraColor.primaryText.color)
                if isMissing {
                    Text(ShelfStrings.missing).font(AuraFont.secondary).foregroundStyle(AuraColor.warning.color)
                        .lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isMissing ? 0.5 : 1)
            if isMissing {
                HStack(spacing: Space.xs) {
                    Button { Task { await service.recover(item.id) } } label: { Image(systemName: "arrow.clockwise") }
                        .help(ShelfStrings.recover).accessibilityLabel(ShelfStrings.recover)
                    Button { service.remove([item.id]) } label: { Image(systemName: "xmark") }
                        .help(ShelfStrings.remove).accessibilityLabel(ShelfStrings.remove)
                }
                .buttonStyle(AuraButtonStyle())
            }
        }
        .padding(Space.sm)
        .frame(width: 92)
        .background(shape.fill(isSelected ? AuraColor.elevatedSurface.color : .clear))
        .overlay { if focused { shape.strokeBorder(AuraColor.accent.color, lineWidth: 2) } }
        .contentShape(shape)
        .overlay {
            // Los ausentes no se arrastran y conservan sus botones; el resto usa la capa de arrastre (solo copia).
            if isMissing {
                Color.clear.allowsHitTesting(false)
            } else {
                ShelfDragSource(ids: { targets }, service: service,
                                onClick: { count, flags in click(count, flags) })
            }
        }
        .onTapGesture(count: 2) { if isMissing { click(2, []) } }
        .onTapGesture { if isMissing { click(1, NSEvent.modifierFlags) } }
        .focusable().focused($focused)
        .onKeyPress(.return) { service.open(targets); return .handled }
        .onKeyPress(.space) { service.select(item.id, extend: true); return .handled }
        .onKeyPress(.delete) { service.remove(targets); return .handled }
        .onKeyPress(.deleteForward) { service.remove(targets); return .handled }
        .onKeyPress(characters: ["a"], phases: .down) { p in
            guard p.modifiers.contains(.command) else { return .ignored }
            service.selectAll(); return .handled
        }
    }

    private func click(_ count: Int, _ flags: NSEvent.ModifierFlags) {
        focused = true
        if count >= 2 { service.select(item.id); service.open([item.id]); return }
        service.select(item.id, extend: flags.contains(.command), range: flags.contains(.shift))
    }

    @ViewBuilder private var icon: some View {
        if isMissing {
            Image(systemName: "questionmark.folder").font(.title).foregroundStyle(AuraColor.secondaryText.color)
        } else if item.kind == .web {
            Image(systemName: "link").font(.title).foregroundStyle(AuraColor.secondaryText.color)
        } else if case .available(let u) = state {
            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().scaledToFit()
        }
    }

    @ViewBuilder private var menu: some View {
        if isMissing {
            Button(ShelfStrings.recover) { Task { await service.recover(item.id) } }
        } else {
            Button(ShelfStrings.open) { service.open(targets) }
            if item.kind == .file { Button(ShelfStrings.reveal) { service.reveal(targets) } }
            Button(ShelfStrings.share) { share(service.shareURLs(targets)) }
            Button(ShelfStrings.airDropSend) { airDrop(service.shareURLs(targets)) }
                .disabled(!ShelfAirDrop.isAvailable(service.shareURLs(targets)))
        }
        Button(item.kind == .web ? ShelfStrings.copyLink : ShelfStrings.copyPath) { service.copyPaths(targets) }
        Divider()
        Button(ShelfStrings.moveEarlier) { service.move(item.id, by: -1) }
        Button(ShelfStrings.moveLater) { service.move(item.id, by: 1) }
        Divider()
        Button(ShelfStrings.remove) { service.remove(targets) }
    }
}
