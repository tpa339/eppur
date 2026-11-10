//
//  Views.swift
//  MoveAI
//
//  Menüleiste, Transkript-Verlauf und Einstellungen.
//

import AppKit
import SwiftUI

// MARK: - Menü

struct MenuView: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Fn halten: sprechen · Klick: Fenster · Ziehen: Bereich")
        Text(serviceStatus)

        Divider()

        if controller.settings.engine == .local {
            Toggle("Qwen-Korrektur", isOn: Bindable(controller.settings).correction)
        }
        Toggle("Automatisch einfügen", isOn: Bindable(controller.settings).autoPaste)
        Toggle("Töne bei Start/Ende", isOn: Bindable(controller.settings).sounds)

        Divider()

        Button("Transkripte …") {
            NSApp.activate()
            openWindow(id: "history")
        }
        .keyboardShortcut("t")

        SettingsLink { Text("Einstellungen …") }
            .keyboardShortcut(",")

        Divider()

        Text("Berechtigungen")
        permissionButton("Bedienungshilfen (Fn-Taste)", granted: Permissions.accessibility) {
            Permissions.requestAccessibility()
            Permissions.openPrivacyPane("Privacy_Accessibility")
        }
        permissionButton("Bildschirmaufnahme (Screenshots)", granted: Permissions.screenRecording) {
            Permissions.requestScreenRecording(force: true)
            Permissions.openPrivacyPane("Privacy_ScreenCapture")
        }
        permissionButton("Mikrofon", granted: Permissions.microphone) {
            Task { await Permissions.requestMicrophone() }
            Permissions.openPrivacyPane("Privacy_Microphone")
        }

        Divider()

        Button("Notchly beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var serviceStatus: String {
        guard controller.settings.engine == .local else { return "Engine: eigene API" }
        let service = MoveAIService.shared
        guard let health = service.health else {
            return "Dienst: " + (service.lastError ?? "startet …")
        }
        let asr = health.asrReady ? "Parakeet ✓" : "Parakeet lädt …"
        let llm = health.correctionReady ? "Qwen ✓" : "Qwen lädt …"
        return "Dienst: \(asr) · \(llm)"
    }

    private func permissionButton(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(granted ? "✓" : "✗")  \(title)")
        }
    }
}

// MARK: - Verlauf

struct HistoryView: View {
    let history: HistoryStore
    let settings: AppSettings
    @State private var search = ""
    @State private var copiedID: UUID?

    private var filtered: [TranscriptEntry] {
        guard !search.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    "Noch keine Transkripte",
                    systemImage: "waveform",
                    description: Text("Halte die Fn-Taste und sprich. Klick auf ein Fenster oder zieh einen Bereich für Screenshots.")
                )
            } else {
                List(filtered) { entry in
                    EntryRow(entry: entry, copied: copiedID == entry.id) {
                        copy(entry)
                    } onDelete: {
                        history.delete(entry)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $search, prompt: "Transkripte durchsuchen")
        .toolbar {
            Button {
                NSWorkspace.shared.open(Storage.baseDirectory)
            } label: {
                Label("Ordner öffnen", systemImage: "folder")
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func copy(_ entry: TranscriptEntry) {
        let images = entry.imagePaths.map { URL(fileURLWithPath: $0) }
        let text = ClipboardWriter.compose(transcript: entry.text, images: images, appendPaths: settings.appendImagePaths)
        ClipboardWriter.write(text: text, images: images, mode: settings.clipboardMode)
        copiedID = entry.id
    }
}

private struct EntryRow: View {
    let entry: TranscriptEntry
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("· \(entry.engine) · \(entry.duration, specifier: "%.1f") s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc", action: onCopy)
                    .labelStyle(.titleAndIcon)
                    .controlSize(.small)
                Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
            }

            if entry.text.isEmpty {
                Text(entry.error.map { "Kein Text – \($0)" } ?? "Kein Text")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(entry.text)
                    .textSelection(.enabled)
                if let raw = entry.rawText, raw != entry.text {
                    DisclosureGroup("Original vor Korrektur") {
                        Text(raw)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }

            if !entry.imagePaths.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(entry.imagePaths, id: \.self) { path in
                            Thumbnail(path: path)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct Thumbnail: View {
    let path: String

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        .help("Doppelklick: in Vorschau öffnen")
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            Tab("Allgemein", systemImage: "gearshape") { GeneralSettings(settings: settings) }
            Tab("Transkription", systemImage: "waveform") { TranscriptionSettings(settings: settings) }
            Tab("Wörterbuch", systemImage: "character.book.closed") { VocabularySettings() }
            Tab("Screenshots", systemImage: "camera.viewfinder") { ScreenshotSettings(settings: settings) }
            Tab("Klänge", systemImage: "speaker.wave.2") { SoundSettings(settings: settings) }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsHint: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchly").font(.title2.weight(.semibold))
                        Text("Fn halten und sprechen. Loslassen fügt den Text ein.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Automatisch in die aktive App einfügen", isOn: $settings.autoPaste)
                Picker("Zwischenablage", selection: $settings.clipboardMode) {
                    ForEach(ClipboardMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Bildpfade an den Text anhängen", isOn: $settings.appendImagePaths)
            } header: {
                Text("Ausgabe")
            } footer: {
                SettingsHint(text: "Der Text landet immer auch in der Zwischenablage. „Text + Bild parallel“: In Claude Code fügt Ctrl+V zusätzlich das erste Bild ein. Mit Bildpfaden kann ein Agent alle Screenshots selbst lesen.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScreenshotSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.captureWindowOnClick) {
                    Label("Klick nimmt das Fenster auf", systemImage: "macwindow")
                }
                Toggle(isOn: $settings.captureRegionOnDrag) {
                    Label("Ziehen nimmt einen Bereich auf", systemImage: "rectangle.dashed")
                }
            } header: {
                Text("Während du Fn hältst")
            } footer: {
                SettingsHint(text: settings.captureWindowOnClick || settings.captureRegionOnDrag
                    ? "Solange Fn gedrückt ist, legt sich eine unsichtbare Ebene über den Bildschirm. Screenshots werden mit dem Text eingefügt."
                    : "Beide aus: Während des Sprechens gehen Klicks ganz normal an deine Apps.")
            }
            Section {
                LabeledContent("Bildschirmaufnahme") {
                    if Permissions.screenRecording {
                        Label("Freigegeben", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Freigeben …") {
                            Permissions.requestScreenRecording(force: true)
                            Permissions.openPrivacyPane("Privacy_ScreenCapture")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Töne bei Start und Ende der Aufnahme", isOn: $settings.sounds)
                if settings.sounds {
                    Picker("Klang", selection: $settings.soundStyle) {
                        ForEach(SoundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Probehören") {
                        HStack {
                            Button("Start", systemImage: "play.fill") { Sounds.recordingStarted(settings.soundStyle) }
                            Button("Ende", systemImage: "stop.fill") { Sounds.recordingStopped(settings.soundStyle) }
                        }
                    }
                }
            } footer: {
                SettingsHint(text: "Ein aufsteigender Klang heißt: Aufnahme läuft. Ein absteigender: Aufnahme beendet.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct VocabularySettings: View {
    @State private var vocabulary = Vocabulary.load()

    var body: some View {
        Form {
            Section {
                TextEditor(text: $vocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 220)
                    .onChange(of: vocabulary) { _, newValue in Vocabulary.save(newValue) }
            } footer: {
                SettingsHint(text: "Eine Zeile pro Name oder Fachbegriff. Ähnlich klingende Erkennungen werden auf diese Schreibweise korrigiert, z. B. „Cloudcode“ → „Claude Code“.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct TranscriptionSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(EngineKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Sprache", selection: $settings.language) {
                    Text("Deutsch").tag("de-DE")
                    Text("Englisch").tag("en-US")
                }
                if settings.engine == .local {
                    Toggle("Nachkorrektur mit Qwen 3.5 2B", isOn: $settings.correction)
                }
            } header: {
                Text("Transkription")
            } footer: {
                if settings.engine == .local {
                    SettingsHint(text: "Läuft komplett lokal im Notchly-Dienst (http://127.0.0.1:\(MoveAIService.port)). Die Korrektur behebt nur Schreibfehler, Namen und Satzzeichen; zu starke Änderungen werden verworfen.")
                }
            }

            if settings.engine == .local {
                Section("Dienst") {
                    ServiceStatusRow()
                }
            }

            if settings.engine == .api {
                Section {
                    TextField("Basis-URL", text: $settings.apiBaseURL, prompt: Text("http://localhost:8000/v1"))
                    TextField("Modell", text: $settings.apiModel, prompt: Text("whisper-1"))
                    SecureField("API-Schlüssel (optional)", text: $settings.apiKey)
                } header: {
                    Text("Eigene API")
                } footer: {
                    Text("Ruft POST {Basis-URL}/audio/transcriptions auf. Funktioniert mit OpenAI und lokalen Whisper-Servern (z. B. speaches, LocalAI). Der Schlüssel liegt im Schlüsselbund.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
    }
}

private struct ServiceStatusRow: View {
    private var service: MoveAIService { .shared }

    var body: some View {
        let health = service.health
        VStack(alignment: .leading, spacing: 6) {
            statusLine("Parakeet (Spracherkennung)", ready: health?.asrReady)
            statusLine("Qwen 3.5 2B (Korrektur)", ready: health?.correctionReady)
            statusLine("yt-dlp (Videos per URL)", ready: health?.ytDlp)
            if health == nil, let error = service.lastError {
                SettingsHint(text: error)
            }
        }
    }

    private func statusLine(_ title: String, ready: Bool?) -> some View {
        HStack {
            Image(systemName: ready == true ? "checkmark.circle.fill" : (ready == nil ? "circle.dotted" : "hourglass"))
                .foregroundStyle(ready == true ? .green : .secondary)
            Text(title)
            Spacer()
            Text(ready == true ? "bereit" : (ready == nil ? "nicht erreichbar" : "lädt …"))
                .foregroundStyle(.secondary)
        }
    }
}
