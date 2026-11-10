//
//  AutoPaste.swift
//  Eppur
//
//  Fügt den Inhalt der Zwischenablage per Cmd+V in die aktive App ein –
//  wie Whisper-Diktier-Apps. Braucht die Freigabe „Bedienungshilfen“.
//

import AppKit
import ApplicationServices

enum AutoPaste {
    /// true, wenn Cmd+V gesendet wurde.
    @discardableResult
    static func paste() -> Bool {
        guard Permissions.accessibility else { return false }
        // Nicht in uns selbst einfügen (z. B. offenes Einstellungsfenster).
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        // Kurz warten, bis die Zwischenablage geschrieben und Fn sicher losgelassen ist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { postCommandV() }
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
