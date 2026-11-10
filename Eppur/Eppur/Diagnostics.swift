//
//  Diagnostics.swift
//  Eppur
//
//  Schreibt Freigabe-Status und Ereignisse nach
//  ~/Library/Application Support/Eppur/app.log (keine Inhalte, nur Status).
//

import AppKit

enum Diagnostics {
    static var logURL: URL { Storage.baseDirectory.appendingPathComponent("app.log") }

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }

    static func permissionSummary() -> String {
        "AX=\(Permissions.accessibility) Screen=\(Permissions.screenRecording) Mic=\(Permissions.microphone)"
    }

    static func logStartup() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        log("Start pid=\(ProcessInfo.processInfo.processIdentifier) path=\(Bundle.main.bundlePath) \(permissionSummary()) front=\(frontmost)")
    }
}
