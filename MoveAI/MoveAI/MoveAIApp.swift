//
//  MoveAIApp.swift
//  MoveAI
//
//  Menüleisten-App: Fn halten → sprechen (+ Screenshots per Klick/Ziehen),
//  Fn loslassen → lokal transkribieren → Text + Bild in die Zwischenablage.
//

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        controller.start()
    }

    /// Nur eine Instanz: zwei Apps würden beide auf Fn reagieren, doppelt einfügen
    /// und sich gegenseitig den Dienst wegnehmen. Die neueste Instanz gewinnt.
    private func terminateOtherInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.processIdentifier != me {
            Diagnostics.log("Beende ältere Instanz pid=\(app.processIdentifier)")
            app.terminate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MoveAIService.shared.stop()
    }
}

@main
struct MoveAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Eppur", systemImage: "waveform") {
            MenuView(controller: delegate.controller)
        }

        Window("Transkripte", id: "history") {
            HistoryView(history: delegate.controller.history, settings: delegate.controller.settings)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView(settings: delegate.controller.settings)
        }
    }
}
