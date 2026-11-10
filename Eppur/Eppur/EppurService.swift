//
//  EppurService.swift
//  Eppur
//
//  Startet und überwacht den lokalen Eppur-Dienst (eppur-server), der
//  Parakeet und das Korrekturmodell im Speicher hält und auf 127.0.0.1 lauscht.
//

import Darwin
import Foundation
import Observation

@Observable
final class EppurService {
    static let shared = EppurService()
    static let port = 47_823
    static let baseURL = URL(string: "http://127.0.0.1:\(port)")!

    /// Erwarteter Installationsort (siehe EppurServer/install.sh).
    static var executableURL: URL {
        Storage.baseDirectory.appendingPathComponent("bin/eppur-server")
    }
    static var logURL: URL { Storage.baseDirectory.appendingPathComponent("server.log") }

    struct Health: Equatable {
        var asrReady = false
        var correctionReady = false
        var ytDlp = false
        var startedAt: Double?
        var pid: Int32?
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
        if let running = await fetchHealth() {
            guard isOutdated(running) else { return true }
            await replaceOutdatedService(running)
        }
        guard isInstalled else {
            lastError = "Dienst nicht installiert – install.sh ausführen"
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

    // MARK: - Updates

    /// Läuft ein Dienst, der älter ist als die installierte Datei (z. B. nach install.sh)?
    private func isOutdated(_ health: Health) -> Bool {
        guard isInstalled,
              let modified = try? FileManager.default.attributesOfItem(atPath: Self.executableURL.path)[.modificationDate] as? Date
        else { return false }
        // Alte Dienste melden keinen Startzeitpunkt → ebenfalls veraltet.
        guard let startedAt = health.startedAt else { return true }
        return modified.timeIntervalSince1970 > startedAt + 1
    }

    private func replaceOutdatedService(_ health: Health) async {
        Diagnostics.log("Veralteter Dienst erkannt – starte neu")
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/shutdown"))
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        _ = try? await URLSession.shared.data(for: request)

        // Ältere Versionen kennen /v1/shutdown nicht: gezielt per PID beenden,
        // aber nur Prozesse, deren Programmpfad exakt unser Dienst ist.
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if await fetchHealth() == nil { return }
        }
        for pid in Self.servicePIDs() {
            Diagnostics.log("Beende alten Dienst pid=\(pid)")
            kill(pid, SIGTERM)
        }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if await fetchHealth() == nil { return }
        }
    }

    /// PIDs aller laufenden Prozesse, deren Programm einer unserer Dienst-Pfade ist.
    private static func servicePIDs() -> [pid_t] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let knownPaths = Set([
            executableURL.path,
            // Frühere Installationsorte und Programmnamen (vor der Umbenennung):
            support.appendingPathComponent("MoveAI/bin/moveai-server").path,
            support.appendingPathComponent("Eppur/bin/moveai-server").path,
        ])
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var result: [pid_t] = []
        var buffer = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            if knownPaths.contains(String(cString: buffer)) { result.append(pid) }
        }
        return result
    }

    private func launch() {
        let process = Process()
        process.executableURL = Self.executableURL
        process.environment = ProcessInfo.processInfo.environment.merging(["EPPUR_PORT": "\(Self.port)"]) { $1 }
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
            ytDlp: json["yt_dlp"] as? Bool ?? false,
            startedAt: json["started_at"] as? Double,
            pid: (json["pid"] as? Int).map { Int32($0) }
        )
        self.health = health
        return health
    }
}
