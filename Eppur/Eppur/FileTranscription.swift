//
//  FileTranscription.swift
//  Eppur
//
//  Audio- und Videodateien per Drag & Drop oder Dateiauswahl transkribieren.
//  Aus Videos (mp4, mov, …) wird nur die Tonspur als m4a herausgelöst.
//  Ausschließlich Spracherkennung: keine LLM-Korrektur, kein Wörterbuch –
//  unabhängig davon, ob die Nachkorrektur für Diktate eingeschaltet ist.
//

import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
final class FileTranscriber {
    struct Job: Identifiable, Equatable {
        let id = UUID()
        let name: String
    }

    /// Wartende und laufende Dateien (die erste läuft).
    private(set) var jobs: [Job] = []
    /// Letzte Meldung, z. B. „Kein Audio: notiz.txt“.
    var message: String?

    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var pending: [(job: Job, url: URL)] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(history: HistoryStore, settings: AppSettings) {
        self.history = history
        self.settings = settings
    }

    /// Dateitypen für die Dateiauswahl.
    static let supportedTypes: [UTType] = [.audio, .movie]

    /// Audio direkt; Videos (mp4, mov, m4v, …) über ihre Tonspur.
    nonisolated static func isAudio(_ url: URL) -> Bool {
        isPlainAudio(url) || isVideo(url)
    }

    nonisolated private static func isPlainAudio(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
    }

    nonisolated private static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    func enqueue(_ urls: [URL]) {
        let audio = urls.filter(Self.isAudio)
        let skipped = urls.filter { !Self.isAudio($0) }
        message = skipped.isEmpty ? nil : "Weder Audio noch Video, übersprungen: " + skipped.map(\.lastPathComponent).joined(separator: ", ")
        for url in audio {
            let job = Job(name: url.lastPathComponent)
            pending.append((job, url))
            jobs.append(job)
        }
        if worker == nil, !pending.isEmpty {
            worker = Task { await drain() }
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let (job, url) = pending.removeFirst()
            await transcribe(url)
            jobs.removeAll { $0.id == job.id }
        }
        worker = nil
    }

    private func transcribe(_ source: URL) async {
        let started = Date()
        var copy: URL?
        var text = ""
        var errorText: String?
        var engineName = "Parakeet · nur Transkription"
        do {
            // Kopie im Sitzungsordner: Der Verlauf bleibt vollständig, auch wenn das
            // Original verschoben wird, und der Dienst braucht keinen Zugriff auf fremde Ordner.
            // Bei Videos nur die Tonspur ablegen: kleiner, und Dienst wie API bekommen reines Audio.
            let dir = try Storage.newSessionDirectory()
            let target: URL
            if Self.isVideo(source) && !Self.isPlainAudio(source) {
                target = dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".m4a")
                try await Self.extractAudio(from: source, to: target)
            } else {
                target = dir.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: target)
            }
            copy = target

            switch settings.engine {
            case .local:
                text = try await Self.transcribeLocally(target, language: settings.language)
            case .api:
                let engine = OpenAICompatibleEngine(
                    baseURL: settings.apiBaseURL, model: settings.apiModel, apiKey: settings.apiKey, correct: false)
                engineName = engine.displayName + " · nur Transkription"
                text = try await engine.transcribe(fileURL: target, language: settings.language).text
            }
        } catch {
            errorText = error.localizedDescription
            Diagnostics.log("Datei-Transkription fehlgeschlagen \(source.lastPathComponent): \(error)")
        }

        let duration = await Self.audioDuration(copy ?? source) ?? Date().timeIntervalSince(started)
        history.add(TranscriptEntry(
            text: text,
            rawText: nil,
            imagePaths: [],
            audioPath: copy?.path,
            engine: engineName,
            duration: duration,
            error: errorText,
            sourceFile: source.lastPathComponent
        ))
    }

    /// Eppur-Dienst liest die Datei direkt (kein Upload in den Speicher), Korrektur aus.
    private static func transcribeLocally(_ file: URL, language: String) async throws -> String {
        guard await EppurService.shared.ensureRunning() else { throw TranscriptionError.serviceUnavailable }
        var request = URLRequest(url: EppurService.baseURL.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        // Lange Aufnahmen brauchen Zeit; Parakeet schafft ein Vielfaches der Echtzeit.
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": file.path, "language": language, "correct": false,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(status) else {
            throw TranscriptionError.http(status, json?["error"] as? String ?? String(decoding: data, as: UTF8.self))
        }
        guard let text = json?["text"] as? String else { throw TranscriptionError.emptyResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Löst die Tonspur eines Videos als AAC/m4a heraus (ohne Neukodierung des Bildes).
    private static func extractAudio(from video: URL, to target: URL) async throws {
        let asset = AVURLAsset(url: video)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw FileTranscriptionError.noAudioTrack
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw FileTranscriptionError.exportUnavailable
        }
        try await session.export(to: target, as: .m4a)
    }

    private static func audioDuration(_ url: URL) async -> TimeInterval? {
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.isNumeric else { return nil }
        return time.seconds
    }
}

enum FileTranscriptionError: LocalizedError {
    case noAudioTrack
    case exportUnavailable

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: "Das Video hat keine Tonspur."
        case .exportUnavailable: "Die Tonspur konnte nicht aus dem Video gelöst werden."
        }
    }
}
