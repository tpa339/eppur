//
//  FnKeyMonitor.swift
//  Eppur
//
//  Erkennt Drücken/Loslassen der Fn-(Globus-)Taste systemweit.
//  Benötigt die Freigabe unter Datenschutz → Bedienungshilfen.
//

import AppKit

final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    /// Fn wurde als Modifier benutzt (z. B. Fn+Pfeil) → Aufnahme verwerfen.
    var onOtherKeyWhileFn: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false
    private static let fnKeyCode: UInt16 = 63 // kVK_Function

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if isDown { onOtherKeyWhileFn?() }
        case .flagsChanged:
            guard event.keyCode == Self.fnKeyCode else { return }
            let down = event.modifierFlags.contains(.function)
            guard down != isDown else { return }
            isDown = down
            down ? onFnDown?() : onFnUp?()
        default:
            break
        }
    }
}
