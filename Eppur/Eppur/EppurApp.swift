//
//  EppurApp.swift
//  Eppur
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
        guard resolveInstances() else { return }
        controller.start()
        if !Permissions.requiredGranted { SetupWindow.shared.show() }
    }

    /// Nur eine Eppur-Instanz – zwei Apps würden beide auf Fn reagieren und doppelt einfügen.
    /// Die installierte App hat Vorrang: Eine Dev-Version (z. B. von Xcode für Code-Snippets
    /// gestartet) beendet sich selbst, wenn Eppur schon läuft. Gleiche Varianten: die neueste gewinnt.
    /// - Returns: false, wenn diese Instanz sich beendet.
    private func resolveInstances() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let myID = Bundle.main.bundleIdentifier ?? ""
        let isDev = myID.hasSuffix(".dev")
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != me, let id = app.bundleIdentifier else { return false }
            return id.hasPrefix("app.eppur.Eppur") || id == "local.moveai.MoveAI"
        }
        if isDev, others.contains(where: { $0.bundleIdentifier == "app.eppur.Eppur" }),
           ProcessInfo.processInfo.environment["EPPUR_DEV_TAKEOVER"] != "1" {
            Diagnostics.log("Dev-Instanz beendet sich: installierte Eppur läuft bereits")
            NSApp.terminate(nil)
            return false
        }
        for app in others {
            Diagnostics.log("Beende andere Instanz \(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)")
            app.terminate()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        EppurService.shared.stop()
    }
}

@main
struct EppurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: delegate.controller)
        } label: {
            // Template-Bild: macOS färbt es passend zu heller/dunkler Menüleiste.
            Image("MenuBarIcon")
                .accessibilityLabel("Eppur")
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
