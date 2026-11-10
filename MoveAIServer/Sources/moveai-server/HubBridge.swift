//
//  HubBridge.swift
//  Handgeschriebene Entsprechung der MLXHuggingFace-Makros
//  (#hubDownloader, #huggingFaceTokenizerLoader), damit Xcode keine
//  Makro-Freigabe braucht.
//

import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

enum HubBridgeError: LocalizedError {
    case invalidRepositoryID(String)
    var errorDescription: String? {
        if case .invalidRepositoryID(let id) = self { return "Ungültige Modell-ID: \(id)" }
        return nil
    }
}

struct HubDownloader: MLXLMCommon.Downloader {
    // Öffentliche Modelle brauchen kein Token. Ein evtl. gespeichertes,
    // abgelaufenes HF-Token würde sonst mit 401 scheitern.
    private let upstream = HubClient(host: URL(string: "https://huggingface.co")!, tokenProvider: .none)

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Foundation.Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw HubBridgeError.invalidRepositoryID(id)
        }
        return try await upstream.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
