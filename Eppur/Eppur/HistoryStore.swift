//
//  HistoryStore.swift
//  Eppur
//
//  Lokaler Verlauf aller Transkripte (JSON in Application Support).
//

import Foundation
import Observation

struct TranscriptEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    /// Unkorrigierter Text, falls die Korrektur etwas geändert hat.
    var rawText: String?
    var imagePaths: [String]
    var audioPath: String?
    var engine: String
    var duration: TimeInterval
    var error: String?
    /// Dateiname, wenn der Eintrag aus einer Audiodatei stammt (nicht aus einem Diktat).
    var sourceFile: String? = nil
}

enum Storage {
    static var baseDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("Eppur", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Einmalige Übernahme der Daten aus dem alten Ordner „MoveAI“.
    static func migrateLegacyDirectory() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support.appendingPathComponent("MoveAI", isDirectory: true)
        let current = support.appendingPathComponent("Eppur", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard fm.fileExists(atPath: current.path) else {
            try? fm.moveItem(at: legacy, to: current)
            return
        }
        // Neuer Ordner existiert schon (z. B. weil der Dienst dort installiert wurde):
        // nur Nutzerdaten übernehmen, die es dort noch nicht gibt. Alte Binaries bleiben zurück.
        for name in ["history.json", "vocabulary.txt", "Sessions", "app.log"] {
            let source = legacy.appendingPathComponent(name)
            let target = current.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) {
                try? fm.moveItem(at: source, to: target)
            }
        }
    }

    static func newSessionDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = baseDirectory
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()) + "_" + UUID().uuidString.prefix(4), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

@Observable
final class HistoryStore {
    private(set) var entries: [TranscriptEntry] = []
    @ObservationIgnored private let fileURL = Storage.baseDirectory.appendingPathComponent("history.json")

    init() {
        load()
    }

    func add(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func delete(_ entry: TranscriptEntry) {
        entries.removeAll { $0.id == entry.id }
        if let dir = (entry.audioPath ?? entry.imagePaths.first).map({ URL(fileURLWithPath: $0).deletingLastPathComponent() }),
           dir.path.hasPrefix(Storage.baseDirectory.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([TranscriptEntry].self, from: data)) ?? []

        // Pfade aus der Zeit vor dem Umzug (…/Application Support/MoveAI/…) anpassen.
        let old = "/Application Support/MoveAI/", new = "/Application Support/Eppur/"
        if entries.contains(where: { $0.imagePaths.contains { $0.contains(old) } || ($0.audioPath?.contains(old) ?? false) }) {
            entries = entries.map { entry in
                var entry = entry
                entry.imagePaths = entry.imagePaths.map { $0.replacingOccurrences(of: old, with: new) }
                entry.audioPath = entry.audioPath?.replacingOccurrences(of: old, with: new)
                return entry
            }
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
