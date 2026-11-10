//
//  Integrations.swift
//  Lokale CLI- und MCP-Schnittstelle: Verlauf lesen, Dateien/URLs transkribieren,
//  Text korrigieren. Nur auf 127.0.0.1, ohne Schlüssel (Entwickleroption).
//
//  MCP über „Streamable HTTP“: POST /mcp mit JSON-RPC 2.0.
//  Einrichten in Claude Code:
//    claude mcp add --transport http eppur http://127.0.0.1:47823/mcp
//

import Foundation

// MARK: - Verlauf (liest history.json der App, schreibt nie)

struct HistoryEntry {
    var id: String
    var date: String
    var text: String
    var rawText: String?
    var imagePaths: [String]
    var engine: String
    var duration: Double

    var json: [String: Any] {
        var d: [String: Any] = ["id": id, "date": date, "text": text, "images": imagePaths,
                                "engine": engine, "duration_s": (duration * 10).rounded() / 10]
        if let rawText { d["raw_text"] = rawText }
        return d
    }
}

enum History {
    static var fileURL: URL { Media.supportDirectory.appendingPathComponent("history.json") }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return HistoryEntry(
                id: id,
                date: item["date"] as? String ?? "",
                text: item["text"] as? String ?? "",
                rawText: item["rawText"] as? String,
                imagePaths: item["imagePaths"] as? [String] ?? [],
                engine: item["engine"] as? String ?? "",
                duration: item["duration"] as? Double ?? 0
            )
        }
    }

    static func search(_ query: String?, limit: Int) -> [HistoryEntry] {
        var entries = load()
        if let query, !query.isEmpty {
            entries = entries.filter {
                $0.text.localizedCaseInsensitiveContains(query) || ($0.rawText?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return Array(entries.prefix(max(1, min(limit, 500))))
    }
}

enum Integrations {
    /// Die App legt diese Datei an, wenn „Lokale CLI & MCP“ ausgeschaltet ist.
    static var isEnabled: Bool {
        !FileManager.default.fileExists(atPath: Media.supportDirectory.appendingPathComponent("integrations-disabled").path)
    }
}

// MARK: - MCP (JSON-RPC 2.0)

enum MCP {
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static let tools: [[String: Any]] = [
        tool("get_latest_transcript", "Neuestes Eppur-Diktat (Text, Rohtext, Screenshot-Pfade).", [:], []),
        tool("list_transcripts", "Letzte Eppur-Diktate, neueste zuerst.",
             ["limit": ["type": "integer", "description": "Anzahl (Standard 10)"]], []),
        tool("search_transcripts", "Volltextsuche im Eppur-Verlauf.",
             ["query": ["type": "string"], "limit": ["type": "integer", "description": "Anzahl (Standard 20)"]], ["query"]),
        tool("get_transcript", "Ein Diktat per ID.", ["id": ["type": "string"]], ["id"]),
        tool("transcribe_file", "Lokale Audio-/Videodatei lokal transkribieren (Parakeet).",
             ["path": ["type": "string", "description": "Absoluter Pfad"],
              "language": ["type": "string", "description": "de, en oder auto (Standard)"],
              "correct": ["type": "boolean", "description": "Nachkorrektur mit Wörterbuch + Qwen"]], ["path"]),
        tool("transcribe_url", "Video-/Audio-URL (z. B. YouTube) per yt-dlp laden und transkribieren.",
             ["url": ["type": "string"],
              "language": ["type": "string", "description": "de, en oder auto (Standard)"],
              "correct": ["type": "boolean"]], ["url"]),
        tool("correct_text", "Text mit Eppur-Wörterbuch und Qwen korrigieren (ohne Umformulieren).",
             ["text": ["type": "string"]], ["text"]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }

    /// Bearbeitet eine JSON-RPC-Nachricht. nil = Benachrichtigung ohne Antwort.
    static func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard id != nil else { return nil } // Notification (z. B. notifications/initialized)

        func result(_ value: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id!, "result": value] }
        func failure(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id!, "error": ["code": code, "message": text]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return result([
                "protocolVersion": supportedVersions.contains(requested) ? requested : supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "eppur", "version": "1.0"],
                "instructions": "Eppur: lokaler Diktat-Verlauf und lokale Transkription (Parakeet + Qwen) auf diesem Mac.",
            ])
        case "ping":
            return result([String: Any]())
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let output = try await callTool(name, args)
                let text = String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
                return result(["content": [["type": "text", "text": text]], "isError": false])
            } catch {
                return result(["content": [["type": "text", "text": "Fehler: \(error.localizedDescription)"]], "isError": true])
            }
        default:
            return failure(-32601, "Unbekannte Methode: \(method)")
        }
    }

    enum ToolError: LocalizedError {
        case missing(String), notFound(String), unknown(String)
        var errorDescription: String? {
            switch self {
            case .missing(let f): "Parameter fehlt: \(f)"
            case .notFound(let id): "Kein Diktat mit ID \(id)"
            case .unknown(let n): "Unbekanntes Werkzeug: \(n)"
            }
        }
    }

    static func callTool(_ name: String, _ args: [String: Any]) async throws -> Any {
        let language = (args["language"] as? String).flatMap { $0 == "auto" ? nil : $0 }
        let correct = bool(args["correct"], default: false)
        switch name {
        case "get_latest_transcript":
            return History.search(nil, limit: 1).first?.json ?? [:]
        case "list_transcripts":
            return History.search(nil, limit: args["limit"] as? Int ?? 10).map(\.json)
        case "search_transcripts":
            guard let query = args["query"] as? String else { throw ToolError.missing("query") }
            return History.search(query, limit: args["limit"] as? Int ?? 20).map(\.json)
        case "get_transcript":
            guard let id = args["id"] as? String else { throw ToolError.missing("id") }
            guard let entry = History.load().first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { throw ToolError.notFound(id) }
            return entry.json
        case "transcribe_file":
            guard let path = args["path"] as? String else { throw ToolError.missing("path") }
            let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: file.path) else { throw MediaError.fileMissing(path) }
            var r = try await process(file: file, language: language, correct: correct, extraVocabulary: [], correctionTimeout: .seconds(60))
            r["source"] = file.path
            return r
        case "transcribe_url":
            guard let url = args["url"] as? String else { throw ToolError.missing("url") }
            let dir = try Media.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let download = try await Media.downloadAudio(from: url, into: dir)
            var r = try await process(file: download.file, language: language, correct: correct, extraVocabulary: [], correctionTimeout: .seconds(60))
            r["source"] = url
            r["title"] = download.title ?? ""
            return r
        case "correct_text":
            guard let text = args["text"] as? String else { throw ToolError.missing("text") }
            let outcome = await corrector.correct(text, vocabulary: Media.vocabulary(), timeout: .seconds(30))
            var r: [String: Any] = ["text": outcome.text, "corrected": outcome.applied]
            if let note = outcome.reason { r["note"] = note }
            return r
        default:
            throw ToolError.unknown(name)
        }
    }
}
