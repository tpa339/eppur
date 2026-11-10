import AppKit

// Gemeinsame Geometrie für App-Icon und Menüleisten-Symbol (Einheit: 0…1 der Fläche).
struct OrbitGeometry {
    static let tilt: CGFloat = 0.26           // Neigung der Bahn (rad), rechts höher wie im Logo
    static let radiusX: CGFloat = 0.37, radiusY: CGFloat = 0.20
    static let planetAngle: CGFloat = 0.85    // Position des Planeten auf der Bahn (rad)

    /// Winkel für n Balken, gleichmäßig nach Bogenlänge verteilt (keine Häufung an den Enden).
    static func evenAngles(_ n: Int) -> [CGFloat] {
        let steps = 2000
        var lengths: [CGFloat] = [0]
        var prev = CGPoint(x: radiusX, y: 0)
        for k in 1...steps {
            let t = CGFloat(k) / CGFloat(steps) * 2 * .pi
            let p = CGPoint(x: cos(t) * radiusX, y: sin(t) * radiusY)
            lengths.append(lengths.last! + hypot(p.x - prev.x, p.y - prev.y)); prev = p
        }
        let total = lengths.last!
        return (0..<n).map { i in
            let target = CGFloat(i) / CGFloat(n) * total
            let k = lengths.firstIndex { $0 >= target } ?? 0
            return CGFloat(k) / CGFloat(steps) * 2 * .pi
        }
    }
    static func point(_ t: CGFloat, center: CGPoint, scale: CGFloat) -> CGPoint {
        let x = cos(t) * radiusX * scale, y = sin(t) * radiusY * scale
        return CGPoint(x: center.x + x * cos(tilt) - y * sin(tilt), y: center.y + x * sin(tilt) + y * cos(tilt))
    }
    static func barHeight(_ i: Int) -> CGFloat {           // Waveform: ruhig variierend
        let pattern: [CGFloat] = [0.35, 0.6, 1.0, 0.75, 0.45, 0.8, 0.55]
        return pattern[i % pattern.count]
    }
}

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawOrbit(_ ctx: CGContext, in rect: CGRect, barCount n: Int, colors: [NSColor]?, barWidthFactor: CGFloat, heightFactor: CGFloat, sunRadius: CGFloat, planetRadius: CGFloat, sunColor: NSColor, planetColor: NSColor) {
    let s = rect.width, c = CGPoint(x: rect.midX, y: rect.midY)
    // Sonne
    ctx.setFillColor(sunColor.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - sunRadius * s, y: c.y - sunRadius * s, width: 2 * sunRadius * s, height: 2 * sunRadius * s))
    // Balken auf der Bahn, Lücke um den Planeten
    let barW = barWidthFactor * s
    for (i, t) in OrbitGeometry.evenAngles(n).enumerated() {
        var d = abs(t - OrbitGeometry.planetAngle); d = min(d, 2 * .pi - d)
        if d < 0.32 { continue }
        let p = OrbitGeometry.point(t, center: c, scale: s)
        let h = (0.035 + 0.045 * OrbitGeometry.barHeight(i)) * heightFactor * s
        // Farbblöcke von links nach rechts (wie im Logo): Cyan → Violett → Magenta
        let rel = (p.x - (c.x - OrbitGeometry.radiusX * s)) / (2 * OrbitGeometry.radiusX * s)
        let color = colors.map { $0[max(0, min(Int(rel * CGFloat($0.count)), $0.count - 1))] } ?? planetColor
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: p.x - barW / 2, y: p.y - h / 2, width: barW, height: h), cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
    }
    // Planet
    let pp = OrbitGeometry.point(OrbitGeometry.planetAngle, center: c, scale: s)
    ctx.setFillColor(planetColor.cgColor)
    ctx.fillEllipse(in: CGRect(x: pp.x - planetRadius * s, y: pp.y - planetRadius * s, width: 2 * planetRadius * s, height: 2 * planetRadius * s))
}

let outDir = CommandLine.arguments[1]
let rgb = { (r: Int, g: Int, b: Int) in NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

// 1) Flaches App-Icon (1024, macOS-Kachel)
let icon = render(size: 1024) { ctx, _ in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(path); ctx.setFillColor(rgb(28, 22, 82).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    drawOrbit(ctx, in: tile, barCount: 30, colors: [rgb(46, 214, 240), rgb(124, 92, 255), rgb(236, 72, 200)],
              barWidthFactor: 0.022, heightFactor: 1.0, sunRadius: 0.095, planetRadius: 0.034,
              sunColor: rgb(255, 214, 140), planetColor: rgb(255, 244, 222))
    ctx.restoreGState()
}
try! icon.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/eppur-icon-flat-1024.png"))

// 2) Menüleisten-Vorschau (schwarz auf transparent), 18 pt @1x/@2x und groß zum Anschauen
for (name, px) in [("menubar-18", 18), ("menubar-36", 36), ("menubar-preview-256", 256)] {
    let rep = render(size: px) { ctx, s in
        drawOrbit(ctx, in: CGRect(x: 0, y: 0, width: s, height: s), barCount: 14, colors: nil,
                  barWidthFactor: 0.06, heightFactor: 1.5, sunRadius: 0.13, planetRadius: 0.065,
                  sunColor: .black, planetColor: .black)
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("ok")
