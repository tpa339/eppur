//
//  SetupWindow.swift
//  Eppur
//
//  Einrichtung: zeigt alle Freigaben mit Live-Status und je einem Knopf.
//  Seite „Einrichtung“ im Hauptfenster; erscheint beim Start automatisch,
//  wenn etwas Notwendiges fehlt – statt überraschender Systemdialoge.
//

import AppKit
import ServiceManagement
import SwiftUI

struct SetupView: View {
    var onDone: () -> Void

    var body: some View {
        // Status jede Sekunde neu lesen (Freigaben ändern sich in den Systemeinstellungen).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Eppur einrichten").font(.title2.weight(.semibold))
                        Text("Einmalig freigeben – danach bleibt es so, auch nach Updates.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    PermissionRow(
                        icon: "mic.fill", title: "Mikrofon", detail: "Aufnahme, solange du Fn hältst.",
                        granted: Permissions.microphone, required: true
                    ) {
                        if Permissions.microphoneUndetermined {
                            Task { await Permissions.requestMicrophone() }
                        } else {
                            Permissions.openPrivacyPane("Privacy_Microphone")
                        }
                    }
                    PermissionRow(
                        icon: "accessibility", title: "Bedienungshilfen", detail: "Fn-Taste erkennen und Text einfügen.",
                        granted: Permissions.accessibility, required: true
                    ) {
                        Permissions.requestAccessibility()
                        Permissions.openPrivacyPane("Privacy_Accessibility")
                    }
                    PermissionRow(
                        icon: "camera.viewfinder", title: "Bildschirmaufnahme", detail: "Nur für Screenshots beim Sprechen.",
                        granted: Permissions.screenRecording, required: false
                    ) {
                        Permissions.requestScreenRecording(force: true)
                        Permissions.openPrivacyPane("Privacy_ScreenCapture")
                    }
                }

                LaunchAtLoginToggle()

                HStack {
                    Text(Permissions.requiredGranted ? "Alles Nötige ist freigegeben." : "Nach dem Freigeben der Bedienungshilfen Eppur einmal neu starten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Fertig", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 480)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let required: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(granted ? Color.green : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.medium))
                    if !required {
                        Text("optional").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Freigegeben", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Freigeben …", action: action)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Startet Eppur automatisch beim Anmelden (nur sinnvoll für die installierte App).
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Eppur beim Anmelden starten", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
