//
//  Views.swift
//  Eppur
//
//  Menüleiste sowie Bausteine für Transkripte und Einstellungen im Hauptfenster.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menü

struct MenuView: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Fn halten: sprechen · Ziehen: Bereich · ½ s halten: Fenster")
        Text(serviceStatus)

        Divider()

        Button("Eppur öffnen …") { WindowOpener.shared.showMain(.home) }
            .keyboardShortcut("o")

        Divider()

        Toggle(controller.settings.correctionProvider == .api ? "Korrektur (API)" : "Korrektur (Qwen lokal)",
               isOn: Bindable(controller.settings).correction)
        Toggle("Automatisch einfügen", isOn: Bindable(controller.settings).autoPaste)
        Toggle("Töne bei Start/Ende", isOn: Bindable(controller.settings).sounds)

        Divider()

        Button("Transkripte …") { WindowOpener.shared.showMain(.transcripts) }
            .keyboardShortcut("t")
        Button("Einstellungen …") { WindowOpener.shared.showMain(.settings) }
            .keyboardShortcut(",")
        Button(Permissions.requiredGranted ? "Einrichtung …" : "⚠︎ Einrichtung – Freigabe fehlt …") {
            WindowOpener.shared.showMain(.setup)
        }

        Divider()

        Button("Eppur beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            // Zweiter Weg zur openWindow-Aktion, falls das Label nicht registriert hat.
            .onAppear { WindowOpener.shared.register(openWindow) }
    }

    private var serviceStatus: String {
        guard controller.settings.engine == .local else { return "Engine: eigene API" }
        let service = EppurService.shared
        guard let health = service.health else {
            return "Dienst: " + (service.lastError ?? "startet …")
        }
        let asr = health.asrReady ? "Parakeet ✓" : "Parakeet lädt …"
        let llm = health.correctionReady ? "Qwen ✓" : "Qwen lädt …"
        return "Dienst: \(asr) · \(llm)"
    }
}

// MARK: - Verlauf (Bausteine für die Seite „Transkripte“ im Hauptfenster)

struct FileJobsBanner: View {
    let files: FileTranscriber

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let current = files.jobs.first {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transkribiere \(current.name) …")
                    if files.jobs.count > 1 {
                        Text("· \(files.jobs.count - 1) in Warteschlange").foregroundStyle(.secondary)
                    }
                }
            }
            if let message = files.message {
                HStack {
                    Text(message).foregroundStyle(.secondary)
                    Spacer()
                    Button("Schließen", systemImage: "xmark") { files.message = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
}

struct EntryRow: View {
    let entry: TranscriptEntry
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var durationText: String {
        guard entry.duration >= 60 else { return String(format: "%.1f s", entry.duration) }
        return Duration.seconds(entry.duration).formatted(.time(pattern: entry.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let file = entry.sourceFile {
                    Label(file, systemImage: "doc.richtext")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file)
                }
                Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("· \(entry.engine) · \(durationText)")
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

private struct SettingsHint: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Group {
            Section {
                LaunchAtLoginToggle()
                Button("Freigaben prüfen …") { WindowOpener.shared.showMain(.setup) }
            } header: {
                Text("Start & Freigaben")
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
    }
}

struct ScreenshotSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Group {
            Section {
                Toggle(isOn: $settings.captureWindowOnClick) {
                    Label("Lang gedrückt halten nimmt das Fenster auf", systemImage: "macwindow")
                }
                Toggle(isOn: $settings.captureRegionOnDrag) {
                    Label("Ziehen nimmt einen Bereich auf", systemImage: "rectangle.dashed")
                }
            } header: {
                Text("Screenshots während du Fn hältst")
            } footer: {
                SettingsHint(text: settings.captureWindowOnClick || settings.captureRegionOnDrag
                    ? "Klicken und Scrollen funktionieren weiter normal – so kannst du während des Sprechens Fenster wechseln. Erst Ziehen oder langes Halten der linken Maustaste löst einen Screenshot aus; er wird mit dem Text eingefügt."
                    : "Beide aus: Während des Sprechens werden keine Screenshots gemacht.")
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
    }
}

struct SoundSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Group {
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
            } header: {
                Text("Klänge")
            } footer: {
                SettingsHint(text: "Ein aufsteigender Klang heißt: Aufnahme läuft. Ein absteigender: Aufnahme beendet.")
            }
        }
    }
}

struct VocabularySettings: View {
    @State private var vocabulary = Vocabulary.load()

    var body: some View {
        Group {
            Section {
                TextEditor(text: $vocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 220)
                    .onChange(of: vocabulary) { _, newValue in Vocabulary.save(newValue) }
            } header: {
                Text("Wörterbuch")
            } footer: {
                SettingsHint(text: "Eine Zeile pro Name oder Fachbegriff. Ähnlich klingende Erkennungen werden auf diese Schreibweise korrigiert, z. B. „Cloudcode“ → „Claude Code“.")
            }
        }
    }
}

struct TranscriptionSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Group {
            Section {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(EngineKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Sprache", selection: $settings.language) {
                    Text("Automatisch (Deutsch/Englisch)").tag("auto")
                    Text("Deutsch").tag("de-DE")
                    Text("Englisch").tag("en-US")
                }
                if settings.engine == .api {
                    TextField("Basis-URL", text: $settings.apiBaseURL, prompt: Text("https://api.openai.com/v1"))
                    TextField("Modell", text: $settings.apiModel, prompt: Text("whisper-1"))
                    SecureField("API-Schlüssel", text: $settings.apiKey)
                }
            } header: {
                Text("Spracherkennung")
            } footer: {
                SettingsHint(text: settings.engine == .local
                    ? "Parakeet läuft lokal im Eppur-Dienst und erkennt Deutsch und Englisch selbst – auch wenn du mitten im Diktat wechselst."
                    : "Ruft POST {Basis-URL}/audio/transcriptions auf (OpenAI oder kompatible Server). Der Schlüssel liegt im Schlüsselbund.")
            }

            Section {
                Toggle("Nachkorrektur", isOn: $settings.correction)
                if settings.correction {
                    Picker("Modell", selection: $settings.correctionProvider) {
                        ForEach(CorrectionProvider.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.correctionProvider == .api {
                        TextField("Basis-URL", text: $settings.correctionBaseURL, prompt: Text("https://openrouter.ai/api/v1"))
                        TextField("Modell", text: $settings.correctionModel, prompt: Text("z. B. openai/gpt-4o-mini"))
                        SecureField("API-Schlüssel", text: $settings.correctionAPIKey)
                    }
                }
            } header: {
                Text("Korrektur")
            } footer: {
                SettingsHint(text: settings.correctionProvider == .api && settings.correction
                    ? "Chat-API im OpenAI-Format: OpenAI (https://api.openai.com/v1), OpenRouter (https://openrouter.ai/api/v1), Ollama (http://localhost:11434/v1) u. a. Der Text verlässt dann deinen Mac. Wörterbuch und Schutz vor Umformulierungen gelten weiter."
                    : "Behebt Schreibfehler, Namen und Satzzeichen mit deinem Wörterbuch. Zu starke Änderungen werden verworfen.")
            }

            Section("Dienst") {
                ServiceStatusRow()
            }

        }
    }
}

private struct ServiceStatusRow: View {
    private var service: EppurService { .shared }

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

// MARK: - Integrationen (lokale CLI & MCP)

struct IntegrationSettings: View {
    @State private var enabled = Integrations.isEnabled
    @State private var copied: String?

    private var mcpCommand: String { "claude mcp add --transport http eppur \(EppurService.baseURL.absoluteString)/mcp" }

    var body: some View {
        Group {
            Section {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lokale CLI & MCP")
                        Text("KI-Agenten und die Kommandozeile können Transkripte lesen, Dateien und Links transkribieren und Text korrigieren. Alles bleibt auf diesem Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: enabled) { _, value in Integrations.setEnabled(value) }

                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).foregroundStyle(.secondary)
                }
            } header: {
                Text("Integrationen")
            } footer: {
                SettingsHint(text: "Ohne Zugriffsschlüssel: Jedes Programm auf diesem Mac kann die Schnittstelle nutzen. Von außen ist sie nicht erreichbar.")
            }

            Section("MCP für KI-Agenten") {
                LabeledContent("Claude Code") {
                    copyButton(mcpCommand, label: "Befehl kopieren")
                }
                Text(mcpCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Section("Kommandozeile") {
                LabeledContent("eppur") {
                    if Integrations.cliInstalled {
                        Label("Installiert", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Nicht installiert – install.sh ausführen").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Ausprobieren") {
                    copyButton("eppur list --limit 3", label: "eppur list --limit 3")
                }
            }
        }
    }

    private var statusColor: Color {
        guard enabled else { return .secondary }
        return EppurService.shared.health != nil ? .green : .orange
    }

    private var statusText: String {
        guard enabled else { return "Ausgeschaltet" }
        return EppurService.shared.health != nil ? "Bedient lokale CLI- und MCP-Clients" : "Dienst startet …"
    }

    private func copyButton(_ text: String, label: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
        } label: {
            Label(copied == text ? "Kopiert" : label, systemImage: copied == text ? "checkmark" : "doc.on.doc")
                .font(.system(.callout, design: text == label ? .monospaced : .default))
        }
    }
}

/// Schalter für den Dienst: Die Datei „integrations-disabled“ sperrt CLI & MCP.
enum Integrations {
    private static var flagURL: URL { Storage.baseDirectory.appendingPathComponent("integrations-disabled") }

    static var isEnabled: Bool { !FileManager.default.fileExists(atPath: flagURL.path) }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            try? FileManager.default.removeItem(at: flagURL)
        } else {
            FileManager.default.createFile(atPath: flagURL.path, contents: Data())
        }
    }

    static var cliInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/eppur").path)
    }
}
