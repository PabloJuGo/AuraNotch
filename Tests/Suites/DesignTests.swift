import AppKit
import AuraCore
import AuraDesignSystem
import SwiftUI

/// Suite de AuraDesignSystem (AURA-003/006/007). Con `AURA_RENDER_DIR=<ruta>` además genera PNG
/// de revisión visual (ImageRenderer, sin ventana).
@MainActor
func runDesignSuite(_ t: SelfCheck) {
    spaceTokens(t)
    motionTokens(t)
    colorTokens(t)
    controlStates(t)
    notchShape(t)
    strings(t)
    if let dir = ProcessInfo.processInfo.environment["AURA_RENDER_DIR"] { renderGallery(t, to: dir) }
}

// MARK: - Espacio y radios

@MainActor private func spaceTokens(_ t: SelfCheck) {
    for s in Space.all { t.expect(s.truncatingRemainder(dividingBy: 4) == 0 && s > 0, "Space \(s) fuera de la rejilla de 4 pt") }
    t.expect(Space.all == [4, 8, 12, 16, 24], "valores de §3.2")
    t.expect(Radius.panel == 20 && Radius.control == 10 && Radius.compact(height: 32) == 16, "radios de §3.2")
}

// MARK: - Movimiento

@MainActor private func motionTokens(_ t: SelfCheck) {
    for tr in Transition.allCases {
        let full = Motion.spec(tr, .full), red = Motion.spec(tr, .reduced), none = Motion.spec(tr, .none)
        t.expect(full.duration == tr.duration && full.curve == .spring && full.bounce == 0, "\(tr) full = catálogo, sin overshoot")
        t.expect(red.duration == tr.duration(for: .reduced) && red.duration <= 0.120 && red.curve == .fade, "\(tr) reduced ≤120 ms fade")
        t.expect(none.duration == 0 && none.curve == .instant, "\(tr) none instantáneo")
        t.expect(Motion.animation(tr, .full) != nil && Motion.animation(tr, .reduced) != nil && Motion.animation(tr, .none) == nil,
                 "\(tr) animation por preferencia")
    }
    t.expect(MotionPreference.resolve(override: nil, systemReduceMotion: true) == .reduced, "sigue Reduce Motion del sistema")
    t.expect(MotionPreference.resolve(override: nil, systemReduceMotion: false) == .full, "sin Reduce Motion = full")
    t.expect(MotionPreference.resolve(override: MotionPreference.none, systemReduceMotion: false) == MotionPreference.none, "override de la app manda")
}

// MARK: - Color

@MainActor private func colorTokens(_ t: SelfCheck) {
    t.expect(RGB.contrast(RGB(white: 0), RGB(white: 1)) > 20.9, "contraste negro/blanco = 21")
    for v in TokenColor.Variant.allCases {
        let surface = AuraColor.surface.rgb(v)
        t.expect(surface == RGB(white: 0), "superficie del notch = negro puro (\(v))")
        for (name, tok) in AuraColor.foregrounds {
            for bg in [AuraColor.surface, AuraColor.elevatedSurface] {
                let c = RGB.contrast(tok.rgb(v), bg.rgb(v))
                t.expect(c >= 4.5, "contraste \(name) \(v) = \(String(format: "%.2f", c)) < 4.5")
            }
        }
    }
    for v in [TokenColor.Variant.lightHighContrast, .darkHighContrast] {
        t.expect(RGB.contrast(AuraColor.separator.rgb(v), AuraColor.surface.rgb(v)) >= 3, "separador en alto contraste ≥3:1")
        for (name, tok) in AuraColor.foregrounds {
            t.expect(RGB.contrast(tok.rgb(v), AuraColor.surface.rgb(v)) >= 7, "AAA en alto contraste: \(name)")
        }
    }
    // Mapeo nombre de apariencia -> variante (las HC no se pueden instanciar fuera de una sesión con
    // «Aumentar contraste»: NSAppearance(named: .accessibilityHighContrast*) devuelve la normal).
    t.expect(TokenColor.variant(named: .accessibilityHighContrastDarkAqua) == .darkHighContrast
             && TokenColor.variant(named: .accessibilityHighContrastAqua) == .lightHighContrast
             && TokenColor.variant(named: .darkAqua) == .dark && TokenColor.variant(named: .aqua) == .light, "mapeo de apariencias")
    // El NSColor dinámico resuelve claro/oscuro a su variante de la tabla.
    for (name, variant) in [(NSAppearance.Name.aqua, TokenColor.Variant.light), (.darkAqua, .dark)] {
        guard let ap = NSAppearance(named: name) else { t.expect(false, "apariencia \(name) inexistente"); continue }
        for (tn, tok) in AuraColor.foregrounds {
            var got: NSColor?
            ap.performAsCurrentDrawingAppearance { got = tok.nsColor.usingColorSpace(.sRGB) }
            let want = tok.rgb(variant)
            let ok = got.map { abs($0.redComponent - want.r) < 0.01 && abs($0.greenComponent - want.g) < 0.01 && abs($0.blueComponent - want.b) < 0.01 } ?? false
            t.expect(ok, "NSColor dinámico \(tn) en \(name)")
        }
    }
}

// MARK: - Estados de control

@MainActor private func controlStates(_ t: SelfCheck) {
    t.expect(ControlState.allCases.count == 8, "8 estados de §3.1")
    for v in TokenColor.Variant.allCases {
        for state in ControlState.allCases where state != .disabled { // disabled está exento de contraste (WCAG 1.4.3)
            for em in [ControlEmphasis.secondary, .primary, .filled] {
                let a = ControlAppearance.resolve(state, emphasis: em)
                let bg = (a.background ?? AuraColor.surface).rgb(v)
                let c = RGB.contrast(a.foreground.rgb(v), bg)
                t.expect(c >= 4.5, "contraste control \(state)/\(em)/\(v) = \(String(format: "%.2f", c))")
            }
        }
    }
    // loading se distingue por el indicador de progreso, no por color.
    let looks = ControlState.allCases.filter { $0 != .loading }.map { ControlAppearance.resolve($0, emphasis: .secondary) }
    for i in looks.indices { for j in looks.indices where i < j {
        t.expect(looks[i] != looks[j], "estados \(i) y \(j) indistinguibles")
    } }
    t.expect(ControlAppearance.resolve(.focus, emphasis: .secondary).showsFocusRing, "focus dibuja anillo")
    t.expect(ControlState.allCases.filter { ControlAppearance.resolve($0, emphasis: .secondary).showsFocusRing } == [.focus], "solo focus tiene anillo")
}

// MARK: - NotchShape

@MainActor private func notchShape(_ t: SelfCheck) {
    let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
    var s = NotchShape(topRadius: 6, bottomRadius: 16)
    let bounds = s.path(in: rect).boundingRect
    t.expect(abs(bounds.minX) < 0.01 && abs(bounds.maxX - 400) < 0.01 && abs(bounds.minY) < 0.01 && abs(bounds.maxY - 200) < 0.01,
             "el path ocupa exactamente el rect (se une al borde superior)")
    // ida y vuelta de animatableData
    let a = NotchShape(topRadius: 6, bottomRadius: 16), b = NotchShape.expanded
    s.animatableData = b.animatableData
    t.expect(s.topRadius == b.topRadius && s.bottomRadius == b.bottomRadius, "animatableData asigna radios")
    s.animatableData = a.animatableData
    t.expect(s.topRadius == 6 && s.bottomRadius == 16, "animatableData ida y vuelta")
    // interpolación lineal sin saltos: la distancia entre pasos consecutivos es acotada y monótona
    var prev = a.path(in: rect).boundingRect
    var lastArea = -1.0
    for i in 0...20 {
        let f = CGFloat(i) / 20
        var m = a
        m.animatableData = AnimatablePair(a.topRadius + (b.topRadius - a.topRadius) * f, a.bottomRadius + (b.bottomRadius - a.bottomRadius) * f)
        let p = m.path(in: rect)
        let bb = p.boundingRect
        t.expect(bb == prev || abs(bb.width - prev.width) < 0.01, "bounding estable en el paso \(i)")
        prev = bb
        // área aproximada por muestreo: crece o decrece monótonamente (no oscila) al interpolar
        var inside = 0
        for x in stride(from: 1.0, to: 400, by: 4.0) { for y in stride(from: 1.0, to: 200, by: 4.0) where p.contains(CGPoint(x: x, y: y)) { inside += 1 } }
        let area = Double(inside)
        t.expect(lastArea < 0 || area <= lastArea + 1, "área monótona al interpolar (paso \(i))")
        lastArea = area
    }
    // tamaños intermedios degenerados: nunca sale del rect ni produce NaN
    for size in [CGSize(width: 0, height: 0), CGSize(width: 10, height: 5), CGSize(width: 40, height: 30), CGSize(width: 300, height: 8)] {
        let r = CGRect(origin: .zero, size: size)
        for shape in [a, b, NotchShape.compact(height: 32), NotchShape(topRadius: 500, bottomRadius: 500)] {
            let bb = shape.path(in: r).boundingRect
            let ok = bb.isNull || (bb.minX >= -0.01 && bb.minY >= -0.01 && bb.maxX <= size.width + 0.01 && bb.maxY <= size.height + 0.01 && !bb.width.isNaN && !bb.height.isNaN)
            t.expect(ok, "path acotado al rect \(size)")
        }
    }
    // el punto bajo el empalme superior queda fuera (cóncavo) y el centro dentro
    let p = a.path(in: rect)
    t.expect(p.contains(CGPoint(x: 200, y: 100)) && !p.contains(CGPoint(x: 0.5, y: 100)), "cuerpo dentro, flanco exterior fuera")
}

// MARK: - Cadenas y símbolos

@MainActor private func strings(_ t: SelfCheck) {
    func symbolOK(_ n: String) -> Bool { NSImage(systemSymbolName: n, accessibilityDescription: nil) != nil }
    var titles = Set<String>(), symbols = Set<String>()
    for m in NotchModule.allCases {
        t.expect(!Strings.moduleTitle(m).isEmpty, "título vacío \(m)")
        t.expect(symbolOK(m.symbolName), "SF Symbol inexistente: \(m.symbolName)")
        titles.insert(Strings.moduleTitle(m)); symbols.insert(m.symbolName)
    }
    t.expect(titles.count == NotchModule.allCases.count && symbols.count == NotchModule.allCases.count, "títulos/símbolos únicos")
    let activities: [ActivityKind] = [.media(playing: true), .media(playing: false), .transfer, .timer, .error]
    var labels = Set<String>()
    for a in activities {
        t.expect(!Strings.activity(a).isEmpty, "etiqueta vacía \(a)")
        t.expect(symbolOK(a.symbolName), "SF Symbol inexistente: \(a.symbolName)")
        labels.insert(Strings.activity(a))
    }
    t.expect(labels.count == activities.count, "etiquetas de actividad únicas")
    for s in [Strings.idle, Strings.moduleNavigation, Strings.settings, Strings.settingsHint, Strings.panelLabel, Strings.retry,
              Strings.openSettings, Strings.cause, Strings.solution, Strings.loading, Strings.success, Strings.failure] {
        t.expect(!s.isEmpty, "cadena común vacía")
    }
    for s in ["gearshape", "checkmark", "exclamationmark.triangle"] { t.expect(symbolOK(s), "SF Symbol \(s)") }
}

// MARK: - Render para revisión visual

@MainActor private func render<V: View>(_ t: SelfCheck, _ name: String, in dir: String, @ViewBuilder _ view: () -> V) {
    let r = ImageRenderer(content: view().environment(\.colorScheme, .dark))
    r.scale = 2
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        t.expect(false, "ImageRenderer no produjo imagen para \(name)"); return
    }
    do { try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")) }
    catch { t.expect(false, "no se pudo escribir \(name): \(error)") }
}

/// Fondo de escritorio neutro para que se vea el borde del negro del notch.
private struct Desk<C: View>: View {
    let content: C
    init(@ViewBuilder _ c: () -> C) { content = c() }
    var body: some View { content.padding(16).background(Color(white: 0.42)) }
}

@MainActor private func renderGallery(_ t: SelfCheck, to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let w: CGFloat = 340, h: CGFloat = 34
    let activities: [(ActivityKind?, String?, Double?)] = [
        (nil, nil, nil), (.media(playing: true), "Nombre de la pista", nil), (.media(playing: false), nil, nil),
        (.transfer, nil, 0.6), (.timer, "04:32", nil), (.error, "Falló", nil),
    ]
    render(t, "compact", in: dir) {
        Desk {
            VStack(spacing: 10) {
                ForEach(activities.indices, id: \.self) { i in
                    let (a, d, p) = activities[i]
                    CompactContent(activity: a, detail: d, progress: p, centerGap: 110)
                        .frame(width: w, height: h)
                        .background(NotchShape.compact(height: h).fill(AuraColor.surface.color))
                }
            }
        }
    }
    let labels: [ControlState] = ControlState.allCases
    render(t, "controls", in: dir) {
        Desk {
            VStack(alignment: .leading, spacing: 8) {
                ForEach([ControlEmphasis.secondary, .filled], id: \.self) { em in
                    HStack(spacing: 8) {
                        ForEach(labels, id: \.self) { s in
                            ControlChrome(state: s, emphasis: em) { Image(systemName: "play.fill") }
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(labels, id: \.self) { s in
                        ControlChrome(state: s, emphasis: .primary) { Text("Abrir").font(AuraFont.body) }
                    }
                }
            }
            .padding(12).background(AuraColor.surface.color)
        }
    }
    render(t, "navbar", in: dir) {
        Desk { ModuleNavBar(selection: .shelf) { _ in }.padding(12).background(AuraColor.surface.color) }
    }
    render(t, "shape-interpolation", in: dir) {
        Desk {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<5, id: \.self) { i in
                    let f = CGFloat(i) / 4
                    NotchShape(topRadius: 6 + 8 * f, bottomRadius: 17 + 3 * f)
                        .fill(AuraColor.surface.color)
                        .frame(width: 90 + 30 * f, height: 34 + 90 * f)
                }
            }
        }
    }
    render(t, "expanded-empty", in: dir) {
        Desk {
            ExpandedChrome(module: .shelf, topInset: 20, onSelect: { _ in }, onOpenSettings: {}) {
                EmptyStateView(symbol: "tray", title: "Estantería vacía",
                               message: "Arrastra archivos aquí para tenerlos a mano. Los originales no se tocan.")
            }
            .frame(width: 420, height: 230)
        }
    }
    render(t, "expanded-error", in: dir) {
        Desk {
            ExpandedChrome(module: .calendar, topInset: 20, onSelect: { _ in }, onOpenSettings: {}) {
                ErrorStateView(title: "No se puede leer el calendario", cause: "Aura Notch no tiene permiso de calendario.",
                               solution: "Concédelo en Ajustes del Sistema > Privacidad.", onRetry: {}, onOpenSettings: {})
            }
            .frame(width: 420, height: 230)
        }
    }
}
