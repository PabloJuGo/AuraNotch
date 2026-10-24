import AuraCore
import SwiftUI

/// Marco del panel expandido (§3.4): cabecera contextual (título del módulo + navegación
/// discreta), contenido del módulo (slot genérico) y pie opcional; los ajustes van en la cabecera.
/// Dibuja su propia silueta `NotchShape` negra; si la ventana host ya dibuja fondo, es inocuo.
/// Orden de foco/VoiceOver: título → navegación → contenido → pie.
public struct ExpandedChrome<Content: View, Footer: View>: View {
    let module: NotchModule
    let modules: [NotchModule]
    let topInset: CGFloat
    let onSelect: (NotchModule) -> Void
    let onOpenSettings: () -> Void
    let content: Content
    let footer: Footer

    /// - Parameter topInset: alto de la zona del notch físico (`safeAreaInsets.top`) que no debe
    ///   ocuparse con contenido.
    public init(module: NotchModule, modules: [NotchModule] = NotchModule.allCases, topInset: CGFloat = 0,
                onSelect: @escaping (NotchModule) -> Void, onOpenSettings: @escaping () -> Void,
                @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.module = module; self.modules = modules; self.topInset = topInset
        self.onSelect = onSelect; self.onOpenSettings = onOpenSettings
        self.content = content(); self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text(Strings.moduleTitle(module))
                    .font(AuraFont.moduleTitle)
                    .foregroundStyle(AuraColor.primaryText.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(3)
                Spacer(minLength: Space.md)
                ModuleNavBar(modules: modules, selection: module, onSelect: onSelect)
                    .accessibilitySortPriority(2)
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(AuraButtonStyle())
                    .help(Strings.settings)
                    .accessibilityLabel(Strings.settings)
                    .accessibilityHint(Strings.settingsHint)
                    .accessibilitySortPriority(0)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilitySortPriority(1)
            // El pie solo ocupa sitio si el módulo aporta acciones propias (los ajustes ya están en la cabecera).
            if Footer.self != EmptyView.self {
                footer.frame(maxWidth: .infinity, alignment: .trailing).accessibilitySortPriority(0)
            }
        }
        .padding(.horizontal, NotchShape.expanded.topRadius + Space.lg) // el cuerpo empieza tras el empalme
        .padding(.bottom, Space.md)
        .padding(.top, topInset + Space.md)
        .background(NotchShape.expanded.fill(AuraColor.surface.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.panelLabel)
    }
}

extension ExpandedChrome where Footer == EmptyView {
    public init(module: NotchModule, modules: [NotchModule] = NotchModule.allCases, topInset: CGFloat = 0,
                onSelect: @escaping (NotchModule) -> Void, onOpenSettings: @escaping () -> Void,
                @ViewBuilder content: () -> Content) {
        self.init(module: module, modules: modules, topInset: topInset, onSelect: onSelect,
                  onOpenSettings: onOpenSettings, content: content, footer: { EmptyView() })
    }
}
