//
//  Transcription.swift
//  Eppur
//
//  Austauschbare Transkriptions-Engines:
//  - Eppur-Dienst (lokal: Parakeet + Qwen-Korrektur, Standard)
//  - OpenAI-kompatible API (/audio/transcriptions) – eigene Server
//

import Foundation
import UniformTypeIdentifiers

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
    let boundary = "Eppur-\(UUID().uuidString)"
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
    let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    let filename = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
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

// MARK: - Eppur-Dienst (lokal)

struct EppurServiceEngine: TranscriptionEngine {
    let correct: Bool
    var remote: CorrectionRemote?
    var displayName: String {
        guard correct else { return "Parakeet" }
        return "Parakeet + " + (remote.map { $0.model } ?? "Qwen")
    }

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
        guard await EppurService.shared.ensureRunning() else { throw TranscriptionError.serviceUnavailable }
        return try await postAudio(
            to: EppurService.baseURL.appendingPathComponent("v1/audio/transcriptions"),
            fileURL: fileURL,
            fields: correctionFields(remote, correct: correct).merging(["language": language]) { $1 },
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
    var correct = false
    var remote: CorrectionRemote?

    var displayName: String { "API (\(model))" + (correct ? " + Korrektur" : "") }

    func transcribe(fileURL: URL, language: String) async throws -> TranscriptionResult {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmedBase), base.scheme != nil else {
            throw TranscriptionError.badURL(baseURL)
        }
        // Kein response_format: JSON ist Standard (OpenAI, OpenRouter), Mistral kennt das Feld nicht.
        var fields = ["model": model]
        // „auto“: keine Sprache vorgeben, die API erkennt sie selbst.
        if language != "auto" {
            fields["language"] = String(language.prefix(while: { $0 != "-" && $0 != "_" }))
        }
        let json = try await postAudio(
            to: base.appendingPathComponent("audio/transcriptions"),
            fileURL: fileURL,
            fields: fields,
            apiKey: apiKey,
            timeout: 120
        )
        guard let rawText = json["text"] as? String else { throw TranscriptionError.emptyResponse }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard correct, !text.isEmpty else { return TranscriptionResult(text: text) }
        // Korrektur (Wörterbuch + LLM) über den Eppur-Dienst; scheitert sie, bleibt der Rohtext.
        return await correctViaService(text)
    }

    private func correctViaService(_ text: String) async -> TranscriptionResult {
        guard await EppurService.shared.ensureRunning() else {
            return TranscriptionResult(text: text, note: "Korrektur übersprungen: Dienst nicht erreichbar")
        }
        var payload: [String: Any] = ["text": text, "timeout": 10]
        correctionFields(remote, correct: true).forEach { key, value in if key != "correct" { payload[key] = value } }
        var request = URLRequest(url: EppurService.baseURL.appendingPathComponent("v1/correct"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let corrected = json["text"] as? String else {
            return TranscriptionResult(text: text, note: "Korrektur fehlgeschlagen")
        }
        let applied = json["corrected"] as? Bool == true
        return TranscriptionResult(text: corrected, rawText: applied ? text : nil, note: json["correction_note"] as? String)
    }
}

/// Felder für den Dienst: lokale oder externe Korrektur.
private func correctionFields(_ remote: CorrectionRemote?, correct: Bool) -> [String: String] {
    var fields = ["correct": correct ? "true" : "false"]
    if correct, let remote {
        fields["correction_base_url"] = remote.baseURL
        fields["correction_model"] = remote.model
        if !remote.apiKey.isEmpty { fields["correction_api_key"] = remote.apiKey }
    }
    return fields
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
