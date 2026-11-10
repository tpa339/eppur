//
//  Speech.swift
//  Spracherkennung mit Parakeet TDT 0.6B v3 (FluidAudio, CoreML/Neural Engine).
//

import FluidAudio
import Foundation

actor SpeechService {
    static let modelName = "parakeet-tdt-0.6b-v3"

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    var isReady: Bool { manager != nil }

    func load() async throws {
        _ = try await readyManager()
    }

    private func readyManager() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        do {
            let ready = try await task.value
            manager = ready
            loading = nil
            return ready
        } catch {
            loading = nil
            throw error
        }
    }

    /// Transkribiert eine Audiodatei (wav, m4a, mp3, caf, …). Lange Dateien
    /// verarbeitet FluidAudio automatisch in Fenstern.
    func transcribe(fileURL: URL, language: String?) async throws -> String {
        let manager = try await readyManager()
        var state = TdtDecoderState.make()
        let hint = language.flatMap { Language(rawValue: String($0.prefix(2)).lowercased()) }
        let result = try await manager.transcribe(fileURL, decoderState: &state, language: hint)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
