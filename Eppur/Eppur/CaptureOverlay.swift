//
//  CaptureOverlay.swift
//  Eppur
//
//  Solange Fn gehalten wird, bleiben Maus und Trackpad normal benutzbar:
//  Klicken, Fenster wechseln und Scrollen gehen direkt an die Apps.
//  Ein Event-Tap hält nur die linke Maustaste kurz zurück und entscheidet:
//  Ziehen → markierter Bereich, lange gedrückt halten → Fenster unter dem Mauszeiger,
//  sonst wird der Klick unverändert an die App nachgereicht.
//  Die Ebene über den Bildschirmen zeichnet nur Markierungen und lässt alle Ereignisse durch.
//

import AppKit

final class CaptureOverlayController {
    var onCapture: ((CaptureTarget) -> Void)?
    private var panels: [CapturePanel] = []
    private let mouse = CaptureMouseTap()

    init() {
        mouse.onSelection = { [weak self] rect in self?.panels.forEach { $0.captureView.selection = rect } }
        mouse.onHighlight = { [weak self] rect in self?.panels.forEach { $0.captureView.highlight = rect } }
        mouse.onCapture = { [weak self] target in self?.onCapture?(target) }
    }

    func show(windowClick: Bool, regionDrag: Bool) {
        hide()
        guard mouse.start(windowHold: windowClick, regionDrag: regionDrag) else { return }
        for screen in NSScreen.screens {
            let panel = CapturePanel(screen: screen)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        mouse.stop()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    func flash(_ cgRect: CGRect) {
        panels.forEach { $0.captureView.flash(cgRect) }
    }
}

/// Fängt während der Aufnahme nur die linke Maustaste ab (siehe Dateikopf).
/// Läuft auf dem Haupt-Runloop, der Callback kommt also auf dem Main-Thread.
final class CaptureMouseTap {
    var onSelection: ((CGRect?) -> Void)?
    var onHighlight: ((CGRect?) -> Void)?
    var onCapture: ((CaptureTarget) -> Void)?

    private enum Gesture {
        case idle
        /// Taste gedrückt, noch unentschieden – der Klick ist zurückgehalten.
        case pending(down: CGEvent, start: CGPoint)
        /// Lange gehalten: Fenster unter dem Mauszeiger ist markiert.
        case windowHold(down: CGEvent, start: CGPoint, id: CGWindowID, frame: CGRect)
        case region(start: CGPoint)
        /// Gehört der App (z. B. Ziehen, wenn Bereichsaufnahme aus ist).
        case passthrough
    }

    /// Kennzeichnet selbst nachgereichte Ereignisse, damit der Tap sie durchlässt.
    private static let replayMarker: Int64 = 0x4570_7075
    private static let dragThreshold: CGFloat = 5
    private static let holdDelay: TimeInterval = 0.5

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = Gesture.idle
    private var holdTimer: DispatchWorkItem?
    private var windowHold = true
    private var regionDrag = true

    @discardableResult
    func start(windowHold: Bool, regionDrag: Bool) -> Bool {
        stop()
        self.windowHold = windowHold
        self.regionDrag = regionDrag
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<CaptureMouseTap>.fromOpaque(userInfo).takeUnretainedValue()
                let pass = MainActor.assumeIsolated { owner.handle(type, event) }
                return pass ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Diagnostics.log("Screenshot-Modus: Event-Tap nicht verfügbar (Bedienungshilfen?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        holdTimer?.cancel()
        holdTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        gesture = .idle
        onSelection?(nil)
        onHighlight?(nil)
    }

    /// true → Ereignis unverändert durchlassen, false → verschlucken.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return true }
        let point = event.location

        switch type {
        case .leftMouseDown:
            guard case .idle = gesture, let copy = event.copy() else { return true }
            gesture = .pending(down: copy, start: point)
            if windowHold { scheduleHold() }
            return false

        case .leftMouseDragged:
            switch gesture {
            case .pending(let down, let start), .windowHold(let down, let start, _, _):
                guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return false }
                holdTimer?.cancel()
                onHighlight?(nil)
                if regionDrag {
                    gesture = .region(start: start)
                    onSelection?(Self.rect(start, point))
                } else {
                    // Bereichsaufnahme aus: Drücken nachreichen, das Ziehen gehört der App.
                    gesture = .passthrough
                    replay(down)
                    replay(event)
                }
                return false
            case .region(let start):
                onSelection?(Self.rect(start, point))
                return false
            case .passthrough, .idle:
                return true
            }

        case .leftMouseUp:
            let finished = gesture
            gesture = .idle
            holdTimer?.cancel()
            switch finished {
            case .pending(let down, _):
                // Normaler Klick: an die App nachreichen (Fenster wechseln, Buttons …).
                replay(down)
                replay(event)
                return false
            case .windowHold(_, _, let id, let frame):
                onHighlight?(nil)
                onCapture?(.window(id, frame))
                return false
            case .region(let start):
                onSelection?(nil)
                let rect = Self.rect(start, point)
                if rect.width >= Self.dragThreshold, rect.height >= Self.dragThreshold {
                    onCapture?(.region(rect))
                }
                return false
            case .passthrough, .idle:
                return true
            }

        default:
            return true
        }
    }

    private func scheduleHold() {
        holdTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, case .pending(let down, let start) = self.gesture,
                  let found = ScreenCapture.windowUnder(start) else { return }
            self.gesture = .windowHold(down: down, start: start, id: found.id, frame: found.frame)
            self.onHighlight?(found.frame)
        }
        holdTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: item)
    }

    private func replay(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        copy.post(tap: .cgSessionEventTap)
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
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
        // Rein optisch: Klicks und Scrollen gehen an die Apps darunter.
        ignoresMouseEvents = true
        canHide = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = captureView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Zeichnet Bereichsauswahl, Fenstermarkierung und Aufnahme-Blitz (Eingaben in CG-Koordinaten).
final class CaptureView: NSView {
    var selection: CGRect? { didSet { needsDisplay = true } }
    var highlight: CGRect? { didSet { needsDisplay = true } }
    private var flashRect: CGRect?

    func flash(_ cgRect: CGRect) {
        flashRect = cgRect
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.flashRect = nil
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let selection, let local = local(selection), local.intersects(bounds) {
            drawSelection(local)
        } else if let highlight, let local = local(highlight), local.intersects(bounds) {
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            local.fill(using: .sourceOver)
            let path = NSBezierPath(roundedRect: local.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            path.lineWidth = 2
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }

        if let flashRect, let local = local(flashRect), local.intersects(bounds) {
            NSColor.white.withAlphaComponent(0.55).setFill()
            local.fill(using: .sourceOver)
        }
    }

    /// CG-Rechteck (global, oben links) → Koordinaten dieser Ansicht.
    private func local(_ cgRect: CGRect) -> NSRect? {
        guard let window else { return nil }
        let screenRect = ScreenGeometry.cocoaRect(fromCG: cgRect)
        return convert(window.convertFromScreen(screenRect), from: nil)
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
}
