//
//  Transcription.swift
//  MoveAI
//
//  Austauschbare Transkriptions-Engines:
//  - MoveAI-Dienst (lokal: Parakeet + Qwen-Korrektur, Standard)
//  - OpenAI-kompatible API (/audio/transcriptions) – eigene Server
//

import Foundation

struct TranscriptionResult {
    var text: String
    /// Unkorrigierter Text, falls eine Korrektur lief.
    var rawText: String?
    var note: String?
}

protocol TranscriptionEngine {
    var displayName: String { get }
    func transcribe(fileURL: URL, language: String) async throws -> TranscriptionResult
}

enum TranscriptionError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case emptyResponse
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .badURL(let url): "Ungültige API-URL: \(url)"
        case .http(let code, let body): "API-Fehler \(code): \(body.prefix(200))"
        case .emptyResponse: "Leere Antwort der API"
        case .serviceUnavailable: "Eppur-Dienst nicht erreichbar"
        }
    }
}

// MARK: - Multipart-Upload (gemeinsam für beide Engines)

private func postAudio(
    to endpoint: URL,
    fileURL: URL,
    fields: [String: String],
    apiKey: String?,
    timeout: TimeInterval
) async throws -> [String: Any] {
    let boundary = "MoveAI-\(UUID().uuidString)"
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let apiKey, !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    var body = Data()
    for (name, value) in fields {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: audio/wav\r\n\r\n")
    body.append(try Data(contentsOf: fileURL))
    body.append("\r\n--\(boundary)--\r\n")

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        throw TranscriptionError.http(status, String(decoding: data, as: UTF8.self))
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TranscriptionError.emptyResponse
    }
    return json
}

// MARK: - MoveAI-Dienst (lokal)

struct MoveAIServiceEngine: TranscriptionEngine {
    let correct: Bool
    var displayName: String { correct ? "Parakeet + Qwen" : "Parakeet" }

    func transcribe(fileURL: URL, language: String) async throws -> TranscriptionResult {
        let json: [String: Any]
        do {
            json = try await send(fileURL: fileURL, language: language)
        } catch let error as URLError {
            // Dienst war kurz weg (z. B. neu gestartet) → einmal neu starten und wiederholen.
            Diagnostics.log("Dienst-Verbindung fehlgeschlagen (\(error.code.rawValue)), neuer Versuch")
            json = try await send(fileURL: fileURL, language: language)
        }
        let text = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = json["raw_text"] as? String
        return TranscriptionResult(
            text: text,
            rawText: (json["corrected"] as? Bool == true) ? raw : nil,
            note: json["correction_note"] as? String
        )
    }

    private func send(fileURL: URL, language: String) async throws -> [String: Any] {
        guard await MoveAIService.shared.ensureRunning() else { throw TranscriptionError.serviceUnavailable }
        return try await postAudio(
            to: MoveAIService.baseURL.appendingPathComponent("v1/audio/transcriptions"),
            fileURL: fileURL,
            fields: ["language": language, "correct": correct ? "true" : "false"],
            apiKey: nil,
            timeout: 120
        )
    }
}

// MARK: - OpenAI-kompatible API

struct OpenAICompatibleEngine: TranscriptionEngine {
    let baseURL: String
    let model: String
    let apiKey: String?

    var displayName: String { "API (\(model))" }

    func transcribe(fileURL: URL, language: String) async throws -> TranscriptionResult {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmedBase), base.scheme != nil else {
            throw TranscriptionError.badURL(baseURL)
        }
        let shortLanguage = String(language.prefix(while: { $0 != "-" && $0 != "_" }))
        let json = try await postAudio(
            to: base.appendingPathComponent("audio/transcriptions"),
            fileURL: fileURL,
            fields: ["model": model, "language": shortLanguage, "response_format": "json"],
            apiKey: apiKey,
            timeout: 120
        )
        guard let text = json["text"] as? String else { throw TranscriptionError.emptyResponse }
        return TranscriptionResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
