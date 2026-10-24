import AppKit
import AuraCore
import AuraDesignSystem
import SwiftUI

/// Historial del portapapeles. Estados: vacío y con elementos. Sin animación permanente.
public struct ClipboardView: View {
    let service: ClipboardService
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(service: ClipboardService) { self.service = service }

    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }
    /// Fijados arriba, conservando el orden por recencia.
    private var rows: [ClipboardItem] { service.items.filter(\.pinned) + service.items.filter { !$0.pinned } }

    public var body: some View {
        Group {
            if service.items.isEmpty {
                EmptyStateView(symbol: "doc.on.clipboard", title: ClipboardStrings.emptyTitle, message: ClipboardStrings.emptyMessage)
            } else {
                VStack(spacing: Space.xs) {
                    HStack {
                        Text(ClipboardStrings.count(service.items.count))
                            .font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                        Spacer(minLength: 0)
                        Button { service.clear() } label: { Image(systemName: "trash") }
                            .buttonStyle(AuraButtonStyle())
                            .help(ClipboardStrings.clear).accessibilityLabel(ClipboardStrings.clear)
                    }
                    ScrollView {
                        LazyVStack(spacing: Space.xs) {
                            ForEach(rows) { item in
                                ClipboardRow(service: service, item: item).transition(Motion.contentTransition(motion))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .animation(Motion.animation(.reorder, motion), value: rows.map(\.id))
                }
            }
        }
        .padding(Space.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ClipboardStrings.group)
    }
}

struct ClipboardRow: View {
    let service: ClipboardService
    let item: ClipboardItem
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var kind: String {
        switch item.content { case .text: ClipboardStrings.text; case .url: ClipboardStrings.link; case .image: ClipboardStrings.image }
    }
    private var summary: String {
        switch item.content {
        case .text(let s): Self.trimmed(s)
        case .url(let u): u.absoluteString
        case .image: ClipboardStrings.image
        }
    }
    private var when: String {
        let now = Date()
        // Un elemento recién copiado puede llevar una fecha unos ms por delante del reloj de la vista («dentro de 0 s»).
        return now.timeIntervalSince(item.date) < 5 ? String(localized: "ahora") : Self.relative.localizedString(for: item.date, relativeTo: now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    /// Una línea recortada: lo que se ve y lo que lee VoiceOver.
    static func trimmed(_ s: String, max: Int = 120) -> String {
        let one = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return one.count > max ? String(one.prefix(max)) + "…" : one
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        HStack(spacing: Space.sm) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).font(AuraFont.body).lineLimit(2).truncationMode(.tail)
                    .foregroundStyle(AuraColor.primaryText.color)
                Text("\(kind) · \(when)").font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
            }
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "pin.fill").font(AuraFont.secondary).foregroundStyle(AuraColor.accent.color)
                    .accessibilityHidden(true)
            }
            if hovering || focused {
                HStack(spacing: Space.xs) {
                    action(item.pinned ? "pin.slash" : "pin", item.pinned ? ClipboardStrings.unpin : ClipboardStrings.pin) { service.togglePin(item.id) }
                    action("xmark", ClipboardStrings.remove) { service.remove(item.id) }
                }
            }
        }
        .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
        .background(shape.fill(hovering ? AuraColor.elevatedSurface.color : .clear))
        .overlay { if focused { shape.strokeBorder(AuraColor.accent.color, lineWidth: 2) } }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { service.copy(item.id) }
        .focusable().focused($focused)
        .onKeyPress(.return) { service.copy(item.id); return .handled }
        .onKeyPress(.delete) { service.remove(item.id); return .handled }
        .onKeyPress(.deleteForward) { service.remove(item.id); return .handled }
        .contextMenu {
            Button(item.pinned ? ClipboardStrings.unpin : ClipboardStrings.pin) { service.togglePin(item.id) }
            Button(ClipboardStrings.remove) { service.remove(item.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind), \(summary), \(when)\(item.pinned ? ", " + ClipboardStrings.pinned : "")")
        .accessibilityHint(ClipboardStrings.copyHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: item.pinned ? ClipboardStrings.unpin : ClipboardStrings.pin) { service.togglePin(item.id) }
        .accessibilityAction(named: ClipboardStrings.remove) { service.remove(item.id) }
    }

    @ViewBuilder private var leading: some View {
        if case .image(let d) = item.content, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).accessibilityHidden(true)
        } else {
            Image(systemName: item.content.symbol).foregroundStyle(AuraColor.secondaryText.color)
                .frame(width: 28, height: 28).accessibilityHidden(true)
        }
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol) }
            .buttonStyle(AuraButtonStyle()).help(label).accessibilityLabel(label)
    }
}

private extension ClipboardContent {
    var symbol: String {
        switch self { case .text: "text.alignleft"; case .url: "link"; case .image: "photo" }
    }
}
