//
//  Media.swift
//  Audio aus URLs (YouTube & Co. via yt-dlp) und Wortliste.
//

import Foundation

enum MediaError: LocalizedError {
    case ytDlpMissing
    case downloadFailed(String)
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .ytDlpMissing: "yt-dlp ist nicht installiert (brew install yt-dlp)"
        case .downloadFailed(let message): "Download fehlgeschlagen: \(message.suffix(400))"
        case .fileMissing(let path): "Datei nicht gefunden: \(path)"
        }
    }
}

enum Media {
    static var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoveAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Eine Zeile pro Name/Begriff; Zeilen mit # werden ignoriert.
    static func vocabulary(extra: [String] = []) -> [String] {
        let url = supportDirectory.appendingPathComponent("vocabulary.txt")
        let fileTerms = (try? String(contentsOf: url, encoding: .utf8))?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") } ?? []
        var seen = Set<String>()
        return (fileTerms + extra).filter { seen.insert($0.lowercased()).inserted }
    }

    static func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moveai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Lädt nur die Tonspur (m4a, ohne ffmpeg) und liefert Datei + Titel.
    static func downloadAudio(from url: String, into directory: URL) async throws -> (file: URL, title: String?) {
        guard let ytDlp = findExecutable("yt-dlp") else { throw MediaError.ytDlpMissing }
        let template = directory.appendingPathComponent("audio.%(ext)s").path
        let output = try await run(ytDlp, [
            "--no-playlist", "--no-progress", "--quiet", "--no-warnings",
            "-f", "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio",
            "--print", "after_move:%(title)s",
            "-o", template, url,
        ])
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.lastPathComponent.hasPrefix("audio.") }) else {
            throw MediaError.downloadFailed(output)
        }
        let title = output.components(separatedBy: .newlines).first { !$0.isEmpty }
        return (file, title)
    }

    static func findExecutable(_ name: String) -> String? {
        // Apps starten Prozesse ohne Login-Shell-PATH → übliche Orte selbst prüfen.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]
            + (ProcessInfo.processInfo.environment["PATH"]?.components(separatedBy: ":") ?? [])
        return paths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: MediaError.downloadFailed(text))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
