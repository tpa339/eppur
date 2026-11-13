//
//  MainWindow.swift
//  Eppur
//
//  Hauptfenster – öffnet sich per Klick auf das App-Symbol (Dock, Finder, Launchpad).
//  Ein Fenster für alles: Seiten werden in der Fensterleiste umgeschaltet. Die Leiste ist auf
//  allen Seiten gleich (keine seitenabhängigen Knöpfe), damit der Wechsel ruhig bleibt.
//  Oben zeigt die Bühne live, was Eppur gerade tut; darunter stehen die Einstellungen
//  als Satz, dessen hervorgehobene Teile sich anklicken und weiterschalten lassen.
//  Gestaltung bewusst ruhig: Systemflächen, hell/dunkel nach System, eine Akzentfarbe
//  (Indigo aus dem App-Symbol, „AccentColor“ im Asset-Katalog).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Seiten im Hauptfenster – alles bleibt in einem Fenster.
enum MainPage: String, CaseIterable, Identifiable {
    case home, transcripts, settings, setup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Jetzt"
        case .transcripts: "Transkripte"
        case .settings: "Einstellungen"
        case .setup: "Einrichtung"
        }
    }
}

/// Öffnet das Hauptfenster auch aus dem AppDelegate (der selbst keine SwiftUI-Umgebung hat)
/// und merkt sich die aktuelle Seite. Das Menüleisten-Symbol ist immer sichtbar und
/// hinterlegt hier die openWindow-Aktion.
@Observable
final class WindowOpener {
    static let shared = WindowOpener()
    var page: MainPage = .home
    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private var pendingMain = false

    /// - Parameter page: Zielseite; nil lässt die zuletzt gezeigte Seite stehen.
    func showMain(_ page: MainPage?) {
        if let page { self.page = page }
        NSApp.activate()
        if let openWindow {
            openWindow(id: "main")
        } else {
            Diagnostics.log("Hauptfenster vorgemerkt: openWindow noch nicht registriert")
            pendingMain = true
        }
    }

    func register(_ action: OpenWindowAction) {
        openWindow = action
        if pendingMain {
            pendingMain = false
            showMain(nil)
        }
    }
}

/// Menüleisten-Symbol; nimmt beim Erscheinen die openWindow-Aktion mit.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Template-Bild: macOS färbt es passend zu heller/dunkler Menüleiste.
        Image("MenuBarIcon")
            .accessibilityLabel("Eppur")
            .onAppear { WindowOpener.shared.register(openWindow) }
    }
}

/// Gemeinsame Abstände aller Seiten.
private enum Metrics {
    static let gutter: CGFloat = 32
    static let pageTop: CGFloat = 24
}

// MARK: - Hauptfenster

struct HomeView: View {
    let controller: AppController
    @Bindable private var nav = WindowOpener.shared
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !controller.files.jobs.isEmpty || controller.files.message != nil {
                FileJobsBanner(files: controller.files)
                    .background(.quaternary.opacity(0.5))
                Divider()
            }

            switch nav.page {
            case .home:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        StageView(controller: controller)
                            .padding(.top, Metrics.pageTop)
                            .padding(.bottom, 32)
                        RecipeView(settings: controller.settings)
                            .padding(.bottom, 40)
                        RecentView(controller: controller) { nav.page = .transcripts }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .transcripts:
                TranscriptsPage(controller: controller)
                    .overlay(alignment: .bottom) { CompactStage(controller: controller) }
            case .settings:
                SettingsPage(settings: controller.settings)
                    .overlay(alignment: .bottom) { CompactStage(controller: controller) }
            case .setup:
                ScrollView {
                    SetupView { nav.page = .home }
                        .padding(.horizontal, Metrics.gutter - 24)
                        .padding(.top, Metrics.pageTop - 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Eppur")
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Seite", selection: $nav.page) {
                    ForEach(MainPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Ordner", systemImage: "folder") { NSWorkspace.shared.open(Storage.baseDirectory) }
                    .help("Datenordner im Finder öffnen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Beenden", systemImage: "power") { NSApp.terminate(nil) }
                    .help("Eppur beenden")
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        Label("Audio ablegen", systemImage: "waveform.badge.plus")
                            .font(.headline)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            controller.files.enqueue(urls)
            return urls.contains(where: FileTranscriber.isAudio)
        } isTargeted: { dropTargeted = $0 }
        // Fenster zu → Fokus an die vorige App zurück, sonst fügt das nächste Diktat nicht ein
        // (Eppur bliebe als Menüleisten-App unsichtbar im Vordergrund).
        .onDisappear { NSApp.hide(nil) }
    }
}

// MARK: Bühne – lebt mit der Aufnahme

private enum StageText {
    static func headline(_ controller: AppController) -> String {
        switch controller.phase {
        case .idle: "Halte Fn und sprich."
        case .recording:
            controller.captureCount > 0
                ? "Höre zu · \(controller.captureCount) Bild\(controller.captureCount == 1 ? "" : "er")"
                : "Höre zu"
        case .transcribing: "Schreibe"
        case .done(let text): text
        case .failed: "Hat nicht geklappt."
        }
    }
}

private struct StageView: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(StageText.headline(controller))
                .font(.system(size: 28, weight: .semibold))
                .contentTransition(.opacity)
                .lineLimit(2)
            Group {
                switch controller.phase {
                case .recording:
                    Waveform(levels: controller.levels, height: 36)
                case .transcribing:
                    ProgressView().controlSize(.small)
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                case .idle, .done:
                    GestureLegend()
                }
            }
            .frame(height: 36, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.2), value: controller.phase)
    }
}

/// Schwebende Statuszeile auf den übrigen Seiten – erscheint nur, wenn etwas passiert,
/// und verschiebt den Seiteninhalt nicht.
private struct CompactStage: View {
    let controller: AppController

    var body: some View {
        if controller.phase != .idle {
            HStack(spacing: 12) {
                Text(StageText.headline(controller))
                    .font(.headline)
                    .lineLimit(1)
                if controller.phase == .recording {
                    Waveform(levels: controller.levels, height: 18)
                } else if controller.phase == .transcribing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.bottom, 16)
        }
    }
}

private struct Waveform: View {
    let levels: [CGFloat]
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: max(4, level * height))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: levels)
    }
}

/// Bedienung in Tastenkappen – kein Erklärtext.
private struct GestureLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            item(key: "fn", text: "sprechen")
            item(key: "ziehen", text: "Bereich")
            item(key: "halten", text: "Fenster")
        }
    }

    private func item(key: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: Einstellungen als Satz

private struct RecipeView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SentenceLayout(spacing: 5, lineSpacing: 9) {
            words("Wenn ich Fn loslasse, hört")
            Token(settings.engine == .local ? "Parakeet" : "meine API", status: engineStatus) {
                settings.engine = settings.engine == .local ? .api : .local
            }
            Token(languagePhrase, action: cycleLanguage)
            words("–")
            Token(correctionPhrase, status: correctionStatus, action: cycleCorrection)
            words("– und Eppur")
            Token(settings.autoPaste ? "fügt den Text direkt ein." : "legt den Text in die Zwischenablage.") {
                settings.autoPaste.toggle()
            }
            words("Ziehen nimmt")
            Token(settings.captureRegionOnDrag ? "einen Bereich" : "nichts") { settings.captureRegionOnDrag.toggle() }
            words("auf, Halten")
            Token(settings.captureWindowOnClick ? "das Fenster." : "nichts.") { settings.captureWindowOnClick.toggle() }
            words("Bilder kommen")
            Token(settings.clipboardMode == .textAndImage ? "neben den Text" : "als Pfad in den Text") {
                settings.clipboardMode = settings.clipboardMode == .textAndImage ? .textOnly : .textAndImage
            }
            if settings.clipboardMode == .textAndImage {
                Token(settings.appendImagePaths ? "mit Pfad." : "ohne Pfad.") { settings.appendImagePaths.toggle() }
            }
            words("Dazu")
            Token(soundPhrase, action: cycleSound)
        }
        .font(.system(size: 18))
        .accessibilityElement(children: .contain)
    }

    private func words(_ text: String) -> some View {
        // Einzelwörter, damit der Satz wie Fließtext umbricht.
        ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
            Text(String(word)).foregroundStyle(.secondary)
        }
    }

    // MARK: Modellstatus als Punkt am Satzteil

    private var engineStatus: Bool? {
        guard settings.engine == .local else { return true }
        return EppurService.shared.health?.asrReady
    }

    private var correctionStatus: Bool?? {
        guard settings.correction, settings.correctionProvider == .local, settings.engine == .local else { return .none }
        return .some(EppurService.shared.health?.correctionReady)
    }

    // Korrektur: Qwen lokal → API → aus → Qwen lokal
    private var correctionPhrase: String {
        guard settings.correction else { return "ohne Korrektur" }
        return settings.correctionProvider == .local ? "Qwen korrigiert lokal" : "eine API korrigiert"
    }

    private func cycleCorrection() {
        if !settings.correction {
            settings.correction = true
            settings.correctionProvider = .local
        } else if settings.correctionProvider == .local {
            settings.correctionProvider = .api
        } else {
            settings.correction = false
        }
    }

    private static let languages: [(tag: String, phrase: String)] = [
        ("auto", "Deutsch und Englisch"),
        ("de-DE", "nur Deutsch"),
        ("en-US", "nur Englisch"),
    ]

    private var languagePhrase: String {
        Self.languages.first { $0.tag == settings.language }?.phrase ?? Self.languages[0].phrase
    }

    private func cycleLanguage() {
        let index = Self.languages.firstIndex { $0.tag == settings.language } ?? 0
        settings.language = Self.languages[(index + 1) % Self.languages.count].tag
    }

    // Klang: Sanft → Tropfen → Glocke → Stille
    private var soundPhrase: String {
        guard settings.sounds else { return "Stille." }
        switch settings.soundStyle {
        case .soft: return "ein sanfter Zweiklang."
        case .bubble: return "ein Tropfen."
        case .chime: return "eine Glocke."
        }
    }

    private func cycleSound() {
        guard settings.sounds else {
            settings.sounds = true
            settings.soundStyle = SoundStyle.allCases[0]
            Sounds.recordingStarted(settings.soundStyle)
            return
        }
        let all = SoundStyle.allCases
        let index = all.firstIndex(of: settings.soundStyle) ?? 0
        if index + 1 < all.count {
            settings.soundStyle = all[index + 1]
            Sounds.recordingStarted(settings.soundStyle)
        } else {
            settings.sounds = false
        }
    }
}

/// Anklickbarer Satzteil: kräftiger als der Fließtext, gestrichelt unterstrichen in der Akzentfarbe.
/// Optional ein Statuspunkt (Modell bereit / lädt / nicht erreichbar).
private struct Token: View {
    let text: String
    let status: Bool??
    let action: () -> Void
    @State private var hovering = false

    init(_ text: String, status: Bool?? = .none, action: @escaping () -> Void) {
        self.text = text
        self.status = status
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if case .some(let ready) = status {
                    Circle()
                        .fill(ready == true ? Color.green : (ready == nil ? Color.red : Color.orange))
                        .frame(width: 6, height: 6)
                        .help(ready == true ? "bereit" : (ready == nil ? "Dienst nicht erreichbar" : "lädt …"))
                }
                Text(text)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(hovering ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) {
                Line()
                    .stroke(Color.accentColor.opacity(hovering ? 1 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2.5]))
                    .frame(height: 1.5)
                    .padding(.horizontal, 4)
                    .offset(y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/// Fließtext-Layout: Kinder nebeneinander, Umbruch bei Platzmangel.
private struct SentenceLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        let rows = rows(width: available, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: available.isFinite ? available : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: Zuletzt gesagt

private struct RecentView: View {
    let controller: AppController
    let openAll: () -> Void
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Zuletzt gesagt").font(.title3.weight(.semibold))
                Spacer()
                if !controller.history.entries.isEmpty {
                    Button("Alle \(controller.history.entries.count)", action: openAll)
                        .buttonStyle(.link)
                }
            }
            .padding(.bottom, 8)

            let recent = Array(controller.history.entries.prefix(3))
            if recent.isEmpty {
                Text("Noch nichts. Audio einfach hierher ziehen.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            ForEach(recent) { entry in
                Divider()
                RecentRow(entry: entry, copied: copiedID == entry.id) { copy(entry) }
            }
        }
    }

    private func copy(_ entry: TranscriptEntry) {
        let settings = controller.settings
        let images = entry.imagePaths.map { URL(fileURLWithPath: $0) }
        let text = ClipboardWriter.compose(transcript: entry.text, images: images, appendPaths: settings.appendImagePaths)
        ClipboardWriter.write(text: text, images: images, mode: settings.clipboardMode)
        copiedID = entry.id
    }
}

private struct RecentRow: View {
    let entry: TranscriptEntry
    let copied: Bool
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text.isEmpty ? (entry.error ?? "Kein Text") : entry.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(entry.text.isEmpty ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text(entry.date, format: .relative(presentation: .named))
                        if !entry.imagePaths.isEmpty {
                            Label("\(entry.imagePaths.count)", systemImage: "photo")
                        }
                        if let file = entry.sourceFile {
                            Text(file).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.accentColor : Color.secondary)
                    .opacity(copied || hovering ? 1 : 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(hovering ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Klicken: wieder in die Zwischenablage")
    }
}

// MARK: Seite „Transkripte“

private struct TranscriptsPage: View {
    let controller: AppController
    @State private var search = ""
    @State private var copiedID: UUID?
    @State private var importing = false

    private var filtered: [TranscriptEntry] {
        guard !search.isEmpty else { return controller.history.entries }
        return controller.history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(search)
                || ($0.sourceFile?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Transkripte durchsuchen", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Button("Audio transkribieren …", systemImage: "waveform.badge.plus") { importing = true }
                    .help("Audiodatei transkribieren (ohne Korrektur) – oder einfach ins Fenster ziehen")
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, Metrics.pageTop)
            .padding(.bottom, 10)

            if controller.history.entries.isEmpty {
                ContentUnavailableView(
                    "Noch nichts gesagt",
                    systemImage: "waveform",
                    description: Text("Halte Fn und sprich – oder zieh eine Audiodatei hierher.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    EntryRow(entry: entry, copied: copiedID == entry.id) {
                        copy(entry)
                    } onDelete: {
                        controller.history.delete(entry)
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { controller.files.enqueue(urls) }
        }
    }

    private func copy(_ entry: TranscriptEntry) {
        let settings = controller.settings
        let images = entry.imagePaths.map { URL(fileURLWithPath: $0) }
        let text = ClipboardWriter.compose(transcript: entry.text, images: images, appendPaths: settings.appendImagePaths)
        ClipboardWriter.write(text: text, images: images, mode: settings.clipboardMode)
        copiedID = entry.id
    }
}

// MARK: Seite „Einstellungen“ – eine durchgehende Liste wie in den Systemeinstellungen

private struct SettingsPage: View {
    let settings: AppSettings

    var body: some View {
        Form {
            TranscriptionSettings(settings: settings)
            VocabularySettings()
            GeneralSettings(settings: settings)
            ScreenshotSettings(settings: settings)
            SoundSettings(settings: settings)
            IntegrationSettings()
        }
        .formStyle(.grouped)
    }
}
