import AuraCore
import SwiftUI

extension NotchModule {
    /// SF Symbol de cada módulo.
    public var symbolName: String {
        switch self {
        case .home: "house"
        case .media: "music.note"
        case .shelf: "tray"
        case .calendar: "calendar"
        case .widgets: "square.grid.2x2"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// Navegación discreta entre módulos. Tab recorre los botones (con Full Keyboard Access);
/// flechas izquierda/derecha cambian la selección. VoiceOver: grupo «Módulos», cada botón
/// con su nombre y el rasgo «seleccionado».
public struct ModuleNavBar: View {
    let modules: [NotchModule]
    let selection: NotchModule
    let onSelect: (NotchModule) -> Void
    private let motion = MotionEnvironment()

    public init(modules: [NotchModule] = NotchModule.allCases, selection: NotchModule,
                onSelect: @escaping (NotchModule) -> Void) {
        self.modules = modules; self.selection = selection; self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(modules, id: \.self) { m in
                Button { onSelect(m) } label: {
                    Image(systemName: m.symbolName).imageScale(.medium)
                }
                .buttonStyle(AuraButtonStyle(emphasis: m == selection ? .filled : .secondary))
                .help(Strings.moduleTitle(m))
                .accessibilityLabel(Strings.moduleTitle(m))
                .accessibilityAddTraits(m == selection ? .isSelected : [])
            }
        }
        .animation(Motion.animation(.switchModule, motion.value), value: selection)
        .onMoveCommand { dir in
            guard let i = modules.firstIndex(of: selection) else { return }
            switch dir {
            case .left where i > 0: onSelect(modules[i - 1])
            case .right where i < modules.count - 1: onSelect(modules[i + 1])
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.moduleNavigation)
    }
}
