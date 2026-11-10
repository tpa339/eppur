//
//  MoveAIApp.swift
//  MoveAI
//
//  Menüleisten-App: Fn halten → sprechen (+ Screenshots per Klick/Ziehen),
//  Fn loslassen → lokal transkribieren → Text + Bild in die Zwischenablage.
//

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController

    override init() {
        // Vor dem Lesen der Einstellungen: Daten der alten App-Identität übernehmen.
        Storage.migrateLegacyDirectory()
        AppSettings.migrateLegacyDefaults()
        controller = AppController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        controller.start()
        if !Permissions.requiredGranted { SetupWindow.shared.show() }
    }

    /// Nur eine Eppur-Instanz – auch zwischen Alltags- und Dev-Version. Zwei Apps
    /// würden beide auf Fn reagieren, doppelt einfügen und sich den Dienst wegnehmen.
    /// Die zuletzt gestartete Instanz gewinnt.
    private func terminateOtherInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != me, let id = app.bundleIdentifier else { return false }
            return id.hasPrefix("app.eppur.Eppur") || id == "local.moveai.MoveAI"
        }
        for app in others {
            Diagnostics.log("Beende andere Instanz \(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)")
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
