//
//  RemoteLLM.swift
//  Korrektur über eine OpenAI-kompatible Chat-API
//  (OpenAI, OpenRouter, Ollama, LM Studio, …): POST {baseURL}/chat/completions
//

import Foundation

struct RemoteLLM: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String?

    enum RemoteError: LocalizedError {
        case badURL(String)
        case http(Int, String)
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case .badURL(let url): "Ungültige Korrektur-URL: \(url)"
            case .http(let code, let body): "Korrektur-API \(code): \(body.prefix(200))"
            case .emptyAnswer: "Leere Antwort der Korrektur-API"
            }
        }
    }

    /// Liest optionale Felder einer Anfrage; nil, wenn keine Remote-Korrektur gewünscht ist.
    static func from(baseURL: String?, model: String?, apiKey: String?) -> RemoteLLM? {
        guard let baseURL, !baseURL.isEmpty, let model, !model.isEmpty else { return nil }
        return RemoteLLM(baseURL: baseURL, model: model, apiKey: apiKey?.isEmpty == true ? nil : apiKey)
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), base.scheme != nil else { throw RemoteError.badURL(baseURL) }

        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        // Von OpenRouter empfohlene, optionale Kennung der App.
        request.setValue("Eppur", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RemoteError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty else {
            throw RemoteError.emptyAnswer
        }
        return content
    }
}
