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
        // Zuerst lesen: currentAppleEvent gilt nur, solange das Start-Event behandelt wird.
        let atLogin = launchedAsLoginItem
        guard resolveInstances() else { return }
        controller.start()
        Diagnostics.log("Startart: \(atLogin ? "Anmeldung" : "von Hand")")
        if !Permissions.requiredGranted {
            WindowOpener.shared.showMain(.setup)
        } else if !atLogin {
            // Von Hand gestartet (Dock, Finder, Launchpad): Hauptfenster zeigen.
            // Beim automatischen Start nach dem Anmelden bleibt Eppur still in der Menüleiste.
            WindowOpener.shared.showMain(nil)
        }
    }

    /// Klick auf das App-Symbol, während Eppur schon läuft.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowOpener.shared.showMain(nil)
        return false
    }

    private var launchedAsLoginItem: Bool {
        // 'oapp' (kAEOpenApplication), 'prdt' (keyAEPropData), 'lgit' (keyAELaunchedAsLogInItem)
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == 0x6F61_7070
            && event.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974
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
            MenuBarLabel()
        }

        Window("Eppur", id: "main") {
            HomeView(controller: delegate.controller)
        }
        .windowToolbarStyle(.unified)
        // Kein Wiederöffnen durch die Zustandswiederherstellung (z. B. beim Autostart).
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 720, height: 720)
    }
}
