//
//  HistoryStore.swift
//  MoveAI
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
}

enum Storage {
    static var baseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoveAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
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
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
