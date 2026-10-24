#!/usr/bin/env swift
// Genera Assets/AppIcon.icns (identidad propia: panel oscuro con silueta de notch). Uso: swift Scripts/make-icon.swift
import AppKit

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), r = s * 0.2237 // radio de la rejilla de iconos de macOS
    let body = NSBezierPath(roundedRect: NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88), xRadius: r, yRadius: r)
    NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.05, alpha: 1))!.draw(in: body, angle: -90)
    // Panel expandido colgando del borde superior (esquinas inferiores redondeadas)
    let w = s*0.56, h = s*0.40, x = (s - w)/2, top = s*0.94 - s*0.0
    let panel = NSBezierPath()
    panel.move(to: NSPoint(x: x, y: top))
    panel.line(to: NSPoint(x: x + w, y: top))
    panel.line(to: NSPoint(x: x + w, y: top - h + s*0.07))
    panel.curve(to: NSPoint(x: x + w - s*0.07, y: top - h), controlPoint1: NSPoint(x: x + w, y: top - h + s*0.03), controlPoint2: NSPoint(x: x + w - s*0.03, y: top - h))
    panel.line(to: NSPoint(x: x + s*0.07, y: top - h))
    panel.curve(to: NSPoint(x: x, y: top - h + s*0.07), controlPoint1: NSPoint(x: x + s*0.03, y: top - h), controlPoint2: NSPoint(x: x, y: top - h + s*0.03))
    panel.close()
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    NSColor.black.setFill(); panel.fill()
    NSColor(white: 1, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: x + w*0.14, y: top - h*0.52, width: w*0.40, height: s*0.035), xRadius: s*0.0175, yRadius: s*0.0175).fill()
    NSColor(white: 1, alpha: 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: x + w*0.14, y: top - h*0.72, width: w*0.62, height: s*0.028), xRadius: s*0.014, yRadius: s*0.014).fill()
    NSColor(srgbRed: 0.25, green: 0.55, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: x + w*0.80, y: top - h*0.60, width: s*0.075, height: s*0.075)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = "Assets/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(base * scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    }
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir, "-o", "Assets/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: dir)
print("Assets/AppIcon.icns generado (exit \(p.terminationStatus))")
