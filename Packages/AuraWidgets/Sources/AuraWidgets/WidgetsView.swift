import AuraCore
import AuraDesignSystem
import SwiftUI

/// UI-09. Tarjetas discretas; activo / deshabilitado / error. Al aparecer/desaparecer avisa al registro
/// (fuera de pantalla ningún widget escucha eventos). Reordenar: menú de la tarjeta o acciones de VoiceOver (AN-08).
public struct WidgetsView: View {
    let registry: WidgetRegistry
    @Environment(\.auraPanelOpen) private var panelOpen
    @Environment(\.auraMotion) private var motionOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: MotionPreference { .resolve(override: motionOverride, systemReduceMotion: reduceMotion) }

    public init(registry: WidgetRegistry) { self.registry = registry }

    public var body: some View {
        Group {
            if registry.entries.isEmpty {
                EmptyStateView(symbol: "square.grid.2x2", title: WidgetStrings.noWidgetsTitle, message: WidgetStrings.noWidgetsMessage)
            } else {
                // Rejilla de 2 columnas por filas: los anchos van solos, los estrechos por parejas y cada fila iguala su alto.
                let entries = registry.entries
                let rows = WidgetGrid.rows(columns: entries.map { $0.widget.manifest.preferredSize.columns })
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Space.sm) {
                        ForEach(rows, id: \.self) { row in
                            HStack(alignment: .top, spacing: Space.sm) {
                                ForEach(row, id: \.self) { i in
                                    WidgetCard(registry: registry, entry: entries[i])
                                        .transition(Motion.contentTransition(motion))
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
            }
        }
        .animation(Motion.animation(.reorder, motion), value: registry.entries.map(\.id))
        .animation(Motion.animation(.switchModule, motion), value: registry.entries.map(\.enabled))
        .onAppear { registry.setVisible(panelOpen) }
        .onChange(of: panelOpen) { _, open in registry.setVisible(open) }
        .onDisappear { registry.setVisible(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WidgetStrings.group)
    }
}

struct WidgetCard: View {
    let registry: WidgetRegistry
    let entry: WidgetRegistry.Entry

    private var widget: any AuraWidget { entry.widget }
    private var m: WidgetManifest { widget.manifest }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            header
            bodyContent
        }
        .padding(Space.md)
        .frame(minHeight: m.preferredSize.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AuraColor.elevatedSurface.color, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .opacity(entry.isUsable ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(m.name)
        .accessibilityAction(named: WidgetStrings.moveEarlier) { registry.move(entry.id, by: -1) }
        .accessibilityAction(named: WidgetStrings.moveLater) { registry.move(entry.id, by: 1) }
        .accessibilityAction(named: entry.enabled ? WidgetStrings.disable : WidgetStrings.enable) { registry.setEnabled(entry.id, !entry.enabled) }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: m.symbol).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).accessibilityHidden(true)
            Text(m.name).font(AuraFont.compact).foregroundStyle(AuraColor.secondaryText.color).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Menu {
                Button(WidgetStrings.moveEarlier) { registry.move(entry.id, by: -1) }.disabled(!registry.canMove(entry.id, by: -1))
                Button(WidgetStrings.moveLater) { registry.move(entry.id, by: 1) }.disabled(!registry.canMove(entry.id, by: 1))
                Divider()
                Button(entry.enabled ? WidgetStrings.disable : WidgetStrings.enable) { registry.setEnabled(entry.id, !entry.enabled) }
                    .disabled(!widget.isAvailable)
            } label: { Text(Image(systemName: "ellipsis")).font(AuraFont.secondary) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(WidgetStrings.options(m.name))
        }
    }

    @ViewBuilder private var bodyContent: some View {
        if !widget.isAvailable {
            note(WidgetStrings.unavailable)
        } else if !entry.enabled {
            note(WidgetStrings.disabled)
        } else {
            switch widget.state {
            case .loading:
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(WidgetStrings.loading).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                }
                .accessibilityElement(children: .combine)
            case .empty(let message):
                note(message)
            case .error(let cause, let solution):
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label(cause, systemImage: "exclamationmark.triangle").font(AuraFont.secondary).foregroundStyle(AuraColor.warning.color)
                    Text(solution).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color)
                    Button(Strings.retry) { widget.retry() }.buttonStyle(AuraButtonStyle(emphasis: .filled))
                }
                .accessibilityElement(children: .contain)
            case .ready:
                widget.makeBody()
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(AuraFont.secondary).foregroundStyle(AuraColor.secondaryText.color).fixedSize(horizontal: false, vertical: true)
    }
}
