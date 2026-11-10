//
//  main.swift
//  Eppur-Dienst – lokale API (nur 127.0.0.1).
//
//  GET  /health
//  POST /v1/audio/transcriptions   multipart: file, language?, correct? (Standard: true), prompt?
//  POST /v1/transcribe             JSON: {"path"|"url", "language"?, "correct"? (Standard: false)}
//  POST /v1/correct                JSON: {"text", "vocabulary"?: [String]}
//

import Foundation

let port = UInt16(ProcessInfo.processInfo.environment["EPPUR_PORT"] ?? ProcessInfo.processInfo.environment["MOVEAI_PORT"] ?? "") ?? 47_823
let speech = SpeechService()
let corrector = CorrectionService()
let startedAt = Date()

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

func bool(_ value: Any?, default fallback: Bool) -> Bool {
    switch value {
    case let b as Bool: b
    case let s as String: ["1", "true", "yes", "ja"].contains(s.lowercased())
    case let n as NSNumber: n.boolValue
    default: fallback
    }
}

/// Transkribieren + optional korrigieren, mit Zeitmessung.
func process(file: URL, language: String?, correct: Bool, extraVocabulary: [String], correctionTimeout: Duration, remote: RemoteLLM? = nil) async throws -> [String: Any] {
    let t0 = Date()
    let raw = try await speech.transcribe(fileURL: file, language: language)
    let asrMs = Int(Date().timeIntervalSince(t0) * 1000)

    var result: [String: Any] = [
        "text": raw,
        "raw_text": raw,
        "corrected": false,
        "asr_model": SpeechService.modelName,
        "asr_ms": asrMs,
    ]
    if correct && !raw.isEmpty {
        let t1 = Date()
        let outcome = await corrector.correct(raw, vocabulary: Media.vocabulary(extra: extraVocabulary), timeout: correctionTimeout, remote: remote)
        result["text"] = outcome.text
        result["corrected"] = outcome.applied
        result["correction_model"] = remote?.model ?? CorrectionService.modelID
        result["correction_ms"] = Int(Date().timeIntervalSince(t1) * 1000)
        if let reason = outcome.reason { result["correction_note"] = reason }
    }
    return result
}

func route(_ request: HTTPRequest) async -> HTTPResponse {
    do {
        // Lokale CLI & MCP (abschaltbar in der App)
        if request.path == "/mcp" || request.path.hasPrefix("/v1/transcripts") {
            guard Integrations.isEnabled else { return .error("Lokale CLI & MCP ist in Eppur ausgeschaltet", status: 403) }
            return try await routeIntegrations(request)
        }
        switch (request.method, request.path) {
        case ("GET", "/health"), ("GET", "/"):
            return .json([
                "status": "ok",
                "asr_model": SpeechService.modelName,
                "asr_ready": await speech.isReady,
                "correction_model": CorrectionService.modelID,
                "correction_ready": await corrector.isReady,
                "yt_dlp": Media.findExecutable("yt-dlp") != nil,
                "uptime_s": Int(Date().timeIntervalSince(startedAt)),
                // Für Updates: Die App startet den Dienst neu, wenn die Datei neuer ist als der Prozess.
                "started_at": startedAt.timeIntervalSince1970,
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "executable": CommandLine.arguments.first ?? "",
            ])

        case ("POST", "/v1/shutdown"):
            log("Beende auf Anfrage")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            return .json(["status": "stopping"])

        case ("POST", "/v1/audio/transcriptions"):
            let parts = Multipart.parse(request.body, contentType: request.header("content-type") ?? "")
            guard let filePart = parts.first(where: { $0.name == "file" }) else {
                return .error("Feld 'file' fehlt", status: 400)
            }
            let fields = Dictionary(parts.filter { $0.name != "file" }.map { ($0.name, $0.string) }, uniquingKeysWith: { a, _ in a })
            let dir = try Media.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let ext = (filePart.filename as NSString?)?.pathExtension.nilIfEmpty ?? "wav"
            let file = dir.appendingPathComponent("upload.\(ext)")
            try filePart.data.write(to: file)
            let remoteFields = RemoteLLM.from(
                baseURL: fields["correction_base_url"], model: fields["correction_model"], apiKey: fields["correction_api_key"])
            let extra = (fields["prompt"] ?? "").components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var result = try await process(
                file: file,
                language: fields["language"],
                correct: bool(fields["correct"], default: true),
                extraVocabulary: extra,
                // Externe APIs brauchen mehr Zeit als das lokale Modell.
                correctionTimeout: .seconds(Double(fields["correction_timeout"] ?? "") ?? (remoteFields == nil ? 3 : 10)),
                remote: remoteFields
            )
            result["source"] = filePart.filename ?? "upload"
            return .json(result)

        case ("POST", "/v1/transcribe"):
            guard let json = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                return .error("JSON erwartet", status: 400)
            }
            let language = json["language"] as? String
            let correct = bool(json["correct"], default: false)
            let timeout = Duration.seconds((json["correction_timeout"] as? Double) ?? 60)
            let extra = json["vocabulary"] as? [String] ?? []
            let remote = RemoteLLM.from(
                baseURL: json["correction_base_url"] as? String, model: json["correction_model"] as? String,
                apiKey: json["correction_api_key"] as? String)

            if let path = json["path"] as? String {
                let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: file.path) else { throw MediaError.fileMissing(path) }
                var result = try await process(file: file, language: language, correct: correct, extraVocabulary: extra, correctionTimeout: timeout, remote: remote)
                result["source"] = file.path
                return .json(result)
            }
            if let url = json["url"] as? String {
                let dir = try Media.temporaryDirectory()
                defer { try? FileManager.default.removeItem(at: dir) }
                let t0 = Date()
                let download = try await Media.downloadAudio(from: url, into: dir)
                var result = try await process(file: download.file, language: language, correct: correct, extraVocabulary: extra, correctionTimeout: timeout, remote: remote)
                result["source"] = url
                result["title"] = download.title ?? ""
                result["download_ms"] = Int(Date().timeIntervalSince(t0) * 1000) - (result["asr_ms"] as? Int ?? 0) - (result["correction_ms"] as? Int ?? 0)
                return .json(result)
            }
            return .error("'path' oder 'url' angeben", status: 400)

        case ("POST", "/v1/correct"):
            guard let json = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let text = json["text"] as? String else {
                return .error("JSON mit 'text' erwartet", status: 400)
            }
            let t0 = Date()
            let outcome = await corrector.correct(
                text,
                vocabulary: Media.vocabulary(extra: json["vocabulary"] as? [String] ?? []),
                timeout: .seconds((json["timeout"] as? Double) ?? 30),
                remote: RemoteLLM.from(
                    baseURL: json["correction_base_url"] as? String, model: json["correction_model"] as? String,
                    apiKey: json["correction_api_key"] as? String)
            )
            var result: [String: Any] = [
                "text": outcome.text, "raw_text": text, "corrected": outcome.applied,
                "correction_ms": Int(Date().timeIntervalSince(t0) * 1000),
            ]
            if let reason = outcome.reason { result["correction_note"] = reason }
            return .json(result)

        default:
            return .error("Unbekannter Pfad \(request.method) \(request.path)", status: 404)
        }
    } catch {
        log("Fehler \(request.path): \(error)")
        return .error(error.localizedDescription, status: 500)
    }
}

func routeIntegrations(_ request: HTTPRequest) async throws -> HTTPResponse {
    switch (request.method, request.path) {
    case ("POST", "/mcp"):
        let parsed = try JSONSerialization.jsonObject(with: request.body)
        if let batch = parsed as? [[String: Any]] {
            var replies: [[String: Any]] = []
            for message in batch { if let reply = await MCP.handle(message) { replies.append(reply) } }
            return replies.isEmpty ? HTTPResponse(status: 202, contentType: "application/json", body: Data()) : .jsonArray(replies)
        }
        guard let message = parsed as? [String: Any] else { return .error("JSON-RPC erwartet", status: 400) }
        guard let reply = await MCP.handle(message) else {
            return HTTPResponse(status: 202, contentType: "application/json", body: Data())
        }
        return .json(reply)
    case ("GET", "/mcp"), ("DELETE", "/mcp"):
        // Kein Server-Push (SSE) nötig: Werkzeuge antworten direkt.
        return .error("Nur POST wird unterstützt", status: 405)
    case ("GET", "/v1/transcripts"):
        let limit = Int(request.query["limit"] ?? "") ?? 20
        return .jsonArray(History.search(request.query["query"], limit: limit).map(\.json))
    case ("GET", "/v1/transcripts/latest"):
        return .json(History.search(nil, limit: 1).first?.json ?? [:])
    case ("GET", _) where request.path.hasPrefix("/v1/transcripts/"):
        let id = String(request.path.dropFirst("/v1/transcripts/".count))
        guard let entry = History.load().first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            return .error("Kein Diktat mit ID \(id)", status: 404)
        }
        return .json(entry.json)
    default:
        return .error("Unbekannter Pfad \(request.method) \(request.path)", status: 404)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Start

let server = try HTTPServer(port: port) { request in
    let t0 = Date()
    let response = await route(request)
    log("\(request.method) \(request.path) → \(response.status) (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
    return response
}
server.start()
log("Eppur-Dienst läuft auf http://127.0.0.1:\(port)")

Task {
    do {
        let t0 = Date()
        try await speech.load()
        log("Spracherkennung bereit (\(SpeechService.modelName), \(Int(Date().timeIntervalSince(t0))) s)")
    } catch {
        log("Spracherkennung konnte nicht geladen werden: \(error)")
    }
}
Task {
    do {
        let t0 = Date()
        try await corrector.load()
        log("Korrektur bereit (\(CorrectionService.modelID), \(Int(Date().timeIntervalSince(t0))) s)")
    } catch {
        log("Korrekturmodell konnte nicht geladen werden: \(error)")
    }
}

dispatchMain()
