import AppKit
import SwiftUI

/// Ecualizador del compacto mientras suena algo. Las barras se animan con Core Animation: el servidor de render las mueve
/// y la app no gasta CPU por fotograma (un `symbolEffect` de SwiftUI costaba ~10 % de CPU medido).
struct WaveBars: NSViewRepresentable {
    var color: Color

    func makeNSView(context: Context) -> WaveBarsView { WaveBarsView() }
    func updateNSView(_ view: WaveBarsView, context: Context) { view.tint = NSColor(color) }
}

final class WaveBarsView: NSView {
    static let barCount = 4, barWidth: CGFloat = 2.5, gap: CGFloat = 2, height: CGFloat = 12
    private var bars: [CALayer] = []
    var tint: NSColor = .white { didSet { bars.forEach { $0.backgroundColor = tint.cgColor } } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.gap, height: Self.height)
    }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        // Duraciones distintas por barra: el conjunto no se repite a la vez y parece música.
        let durations: [CFTimeInterval] = [0.52, 0.38, 0.62, 0.45]
        let lows: [Float] = [0.30, 0.22, 0.35, 0.25]
        for i in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = tint.cgColor
            bar.cornerRadius = Self.barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.height)
            bar.position = CGPoint(x: Self.barWidth / 2 + CGFloat(i) * (Self.barWidth + Self.gap), y: Self.height / 2)
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = lows[i]; a.toValue = 1
            a.duration = durations[i]; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.timeOffset = Double(i) * 0.17
            bar.add(a, forKey: "wave")
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }
}
