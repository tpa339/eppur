//
//  CaptureOverlay.swift
//  Eppur
//
//  Solange Fn gehalten wird: transparente Ebene über allen Bildschirmen.
//  Klick → Fenster unter dem Mauszeiger; Ziehen → markierter Bereich.
//  Das Panel aktiviert die App nicht, der Fokus bleibt z. B. im Terminal.
//

import AppKit

final class CaptureOverlayController {
    var onCapture: ((CaptureTarget) -> Void)?
    private var panels: [CapturePanel] = []

    func show(windowClick: Bool, regionDrag: Bool) {
        hide()
        for screen in NSScreen.screens {
            let panel = CapturePanel(screen: screen)
            panel.captureView.allowsWindowClick = windowClick
            panel.captureView.allowsRegionDrag = regionDrag
            panel.captureView.onCapture = { [weak self] target in self?.onCapture?(target) }
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSCursor.crosshair.set()
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
    }

    func flash(_ cgRect: CGRect) {
        panels.forEach { $0.captureView.flash(cgRect) }
    }
}

final class CapturePanel: NSPanel {
    let captureView: CaptureView

    init(screen: NSScreen) {
        captureView = CaptureView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = captureView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class CaptureView: NSView {
    var onCapture: ((CaptureTarget) -> Void)?
    var allowsWindowClick = true
    var allowsRegionDrag = true

    private var hover: (id: CGWindowID, cgFrame: CGRect)?
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var flashRect: NSRect?
    private var trackingArea: NSTrackingArea?

    private let dragThreshold: CGFloat = 5

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { updateHover(atScreen: NSEvent.mouseLocation, in: window) }
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: Maus

    /// Scrollen geht durch die Screenshot-Ebene hindurch an die App unter dem Mauszeiger –
    /// so lässt sich beim Diktieren durch lange Seiten scrollen und mehrfach markieren.
    override func scrollWheel(with event: NSEvent) {
        guard let window, let cgEvent = event.cgEvent?.copy() else { return }
        let cocoaPoint = window.convertPoint(toScreen: event.locationInWindow)
        guard let pid = ScreenCapture.ownerPIDUnder(ScreenGeometry.cgPoint(fromCocoa: cocoaPoint)) else { return }
        cgEvent.postToPid(pid)
        // Fensterrahmen kann sich durch das Scrollen nicht ändern, Inhalt schon: Markierung neu zeichnen.
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let window else { return }
        updateHover(atScreen: window.convertPoint(toScreen: event.locationInWindow), in: window)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
        guard let window, let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)

        if hypot(end.x - start.x, end.y - start.y) < dragThreshold {
            guard allowsWindowClick else { return }
            updateHover(atScreen: window.convertPoint(toScreen: event.locationInWindow), in: window)
            if let hover { onCapture?(.window(hover.id, hover.cgFrame)) }
        } else {
            guard allowsRegionDrag else { return }
            let viewRect = Self.rect(start, end)
            let screenRect = window.convertToScreen(convert(viewRect, to: nil))
            onCapture?(.region(ScreenGeometry.cgRect(fromCocoa: screenRect)))
        }
    }

    // MARK: Darstellung

    func flash(_ cgRect: CGRect) {
        guard let window else { return }
        let screenRect = ScreenGeometry.cocoaRect(fromCG: cgRect)
        let local = convert(window.convertFromScreen(screenRect), from: nil)
        guard local.intersects(bounds) else { return }
        flashRect = local
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.flashRect = nil
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fast unsichtbar, aber > 0, damit Klicks nicht durchfallen.
        NSColor(white: 0, alpha: 0.012).setFill()
        bounds.fill()

        if allowsRegionDrag, let start = dragStart, let current = dragCurrent, hypot(current.x - start.x, current.y - start.y) >= dragThreshold {
            drawSelection(Self.rect(start, current))
        } else if allowsWindowClick, let hover, let window {
            let screenRect = ScreenGeometry.cocoaRect(fromCG: hover.cgFrame)
            let local = convert(window.convertFromScreen(screenRect), from: nil)
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            local.fill(using: .sourceOver)
            let path = NSBezierPath(roundedRect: local.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            path.lineWidth = 2
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }

        if let flashRect {
            NSColor.white.withAlphaComponent(0.55).setFill()
            flashRect.fill(using: .sourceOver)
        }
    }

    private func drawSelection(_ rect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: rect))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dim.fill()

        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let origin = NSPoint(x: rect.maxX + 6, y: rect.minY - size.height - 6)
        let background = NSRect(origin: origin, size: size).insetBy(dx: -5, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        label.draw(at: origin, withAttributes: attributes)
    }

    private func updateHover(atScreen cocoaPoint: NSPoint, in window: NSWindow) {
        let found = ScreenCapture.windowUnder(ScreenGeometry.cgPoint(fromCocoa: cocoaPoint))
        if found?.id != hover?.id || found?.frame != hover?.cgFrame {
            hover = found.map { ($0.id, $0.frame) }
            needsDisplay = true
        }
    }

    private static func rect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
