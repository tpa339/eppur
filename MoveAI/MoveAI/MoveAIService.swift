//
//  MoveAIService.swift
//  MoveAI
//
//  Startet und überwacht den lokalen MoveAI-Dienst (moveai-server), der
//  Parakeet und das Korrekturmodell im Speicher hält und auf 127.0.0.1 lauscht.
//

import Foundation
import Observation

@Observable
final class MoveAIService {
    static let shared = MoveAIService()
    static let port = 47_823
    static let baseURL = URL(string: "http://127.0.0.1:\(port)")!

    /// Erwarteter Installationsort (siehe MoveAIServer/install.sh).
    static var executableURL: URL {
        Storage.baseDirectory.appendingPathComponent("bin/moveai-server")
    }
    static var logURL: URL { Storage.baseDirectory.appendingPathComponent("server.log") }

    struct Health: Equatable {
        var asrReady = false
        var correctionReady = false
        var ytDlp = false
    }

    private(set) var health: Health?
    private(set) var lastError: String?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: Self.executableURL.path) }

    func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task {
            _ = await ensureRunning()
            while !Task.isCancelled {
                await refreshHealth()
                try? await Task.sleep(for: .seconds(health?.asrReady == true && health?.correctionReady == true ? 30 : 3))
            }
        }
    }

    /// Prüft, ob der Dienst antwortet; startet ihn sonst und wartet kurz.
    @discardableResult
    func ensureRunning() async -> Bool {
        if await fetchHealth() != nil { return true }
        guard isInstalled else {
            lastError = "Dienst nicht installiert – MoveAIServer/install.sh ausführen"
            return false
        }
        if process?.isRunning != true { launch() }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if await fetchHealth() != nil { return true }
        }
        lastError = "Dienst startet nicht – siehe \(Self.logURL.path)"
        return false
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func launch() {
        let process = Process()
        process.executableURL = Self.executableURL
        process.environment = ProcessInfo.processInfo.environment.merging(["MOVEAI_PORT": "\(Self.port)"]) { $1 }
        // Anhängen statt überschreiben, damit Abstürze nachvollziehbar bleiben.
        if !FileManager.default.fileExists(atPath: Self.logURL.path) {
            FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: Self.logURL) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
            self.process = process
            lastError = nil
        } catch {
            lastError = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func refreshHealth() async {
        health = await fetchHealth()
    }

    private func fetchHealth() async -> Health? {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let health = Health(
            asrReady: json["asr_ready"] as? Bool ?? false,
            correctionReady: json["correction_ready"] as? Bool ?? false,
            ytDlp: json["yt_dlp"] as? Bool ?? false
        )
        self.health = health
        return health
    }
}
