//
//  Permissions.swift
//  MoveAI
//

import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    private static var askedScreenRecording = false

    /// Fragt höchstens einmal pro App-Start (der Systemdialog nervt sonst bei jedem Screenshot).
    static func requestScreenRecording(force: Bool = false) {
        guard force || !askedScreenRecording else { return }
        askedScreenRecording = true
        _ = CGRequestScreenCaptureAccess()
    }

    static var microphone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var microphoneUndetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    /// Ohne Mikrofon und Bedienungshilfen funktioniert der Kernablauf nicht.
    static var requiredGranted: Bool { microphone && accessibility }

    @discardableResult
    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
