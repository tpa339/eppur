import AppKit

// App-Icon und Menüleisten-Symbol: bewegtes „e“ (Spuren in Cyan/Violett) mit Mauszeiger.
// „Eppur si muove“ – das „e“ bewegt sich; der Zeiger steht für Screenshots per Klick.
//
// Aufruf (aus dem Repo-Wurzelordner):
//   swift Eppur/design/render-icons.swift Eppur
// schreibt Eppur/design/eppur-icon-flat-1024.png, alle Größen in AppIcon.appiconset
// und menubar.png/@2x in MenuBarIcon.imageset.

let rgb = { (r: Int, g: Int, b: Int) in NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }
let navy = rgb(28, 22, 82), cream = rgb(255, 244, 222)
let cyan = rgb(45, 212, 238), violet = rgb(130, 90, 255)

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Glyphen-Pfad des „e“ (SF Rounded, Heavy), Mittelpunkt der Bounding-Box im Ursprung.
func ePath(_ size: CGFloat) -> CGPath {
    var font = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: size) { font = r }
    var ch: [UniChar] = Array("e".utf16), g = [CGGlyph](repeating: 0, count: 1)
    CTFontGetGlyphsForCharacters(font as CTFont, &ch, &g, 1)
    let p = CTFontCreatePathForGlyph(font as CTFont, g[0], nil)!
    var t = CGAffineTransform(translationX: -p.boundingBox.midX, y: -p.boundingBox.midY)
    return p.copy(using: &t)!
}

/// Klassischer Mauszeiger; Spitze bei tip, Höhe h, leicht gedreht.
func cursorPath(tip: CGPoint, h: CGFloat, rot: CGFloat) -> CGPath {
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.1, 13.1), (6.9, 19.6), (9.9, 18.4), (7.2, 12.1), (12.6, 12.1)]
    let u = h / 20
    let p = CGMutablePath()
    p.addLines(between: pts.map { CGPoint(x: $0.0 * u, y: -$0.1 * u) },
               transform: CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: rot))
    p.closeSubpath()
    return p
}

/// Motiv in einem quadratischen Bereich der Kantenlänge s (Ursprung unten links).
func drawMotif(_ ctx: CGContext, _ s: CGFloat) {
    let e = ePath(s * 0.6), c = CGPoint(x: s * 0.46, y: s * 0.52), step = s * 0.06
    for (i, col) in [cyan.withAlphaComponent(0.55), violet.withAlphaComponent(0.8), cream].enumerated() {
        ctx.saveGState()
        ctx.translateBy(x: c.x + CGFloat(i - 2) * step, y: c.y)
        ctx.addPath(e); ctx.setFillColor(col.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }
    let cursor = cursorPath(tip: CGPoint(x: s * 0.63, y: s * 0.45), h: s * 0.27, rot: 0.12)
    ctx.addPath(cursor); ctx.setLineJoin(.round); ctx.setLineWidth(s * 0.03); ctx.setStrokeColor(navy.cgColor); ctx.strokePath()
    ctx.addPath(cursor); ctx.setFillColor(cream.cgColor); ctx.fillPath()
}

/// macOS-Kachel (824/1024 der Fläche, Rand für den Schatten) mit Motiv.
func appIcon(size: Int) -> NSBitmapImageRep {
    render(size: size) { ctx, s in
        let k = s / 1024
        let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = CGPath(roundedRect: tile, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path); ctx.setFillColor(navy.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.clip()
        drawMotif(ctx, s)
    }
}

/// Template-Symbol für die Menüleiste: „e“ und Zeiger in Schwarz, Zeiger mit Freistellung.
func menubar(size: Int) -> NSBitmapImageRep {
    render(size: size) { ctx, s in
        ctx.saveGState()
        ctx.translateBy(x: s * 0.4, y: s * 0.56)
        ctx.addPath(ePath(s * 1.0)); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
        let cursor = cursorPath(tip: CGPoint(x: s * 0.55, y: s * 0.5), h: s * 0.5, rot: 0.12)
        ctx.saveGState(); ctx.setBlendMode(.clear)
        ctx.addPath(cursor); ctx.setLineJoin(.round); ctx.setLineWidth(s * 0.12); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(cursor); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    }
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Eppur"
let assets = "\(root)/Eppur/Assets.xcassets"

write(appIcon(size: 1024), "\(root)/design/eppur-icon-flat-1024.png")
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for sc in scales {
        write(appIcon(size: pt * sc), "\(assets)/AppIcon.appiconset/icon_\(pt)\(sc == 2 ? "@2x" : "").png")
    }
}
write(menubar(size: 18), "\(assets)/MenuBarIcon.imageset/menubar.png")
write(menubar(size: 36), "\(assets)/MenuBarIcon.imageset/menubar@2x.png")
write(menubar(size: 256), "\(root)/design/eppur-menubar-preview.png")
print("ok")
