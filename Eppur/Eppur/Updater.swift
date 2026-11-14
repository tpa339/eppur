//
//  Updater.swift
//  Eppur
//
//  Updates über GitHub Releases: sucht die neueste Version, lädt das ZIP,
//  prüft die Signatur (gleicher Signierer wie die laufende App), ersetzt die App
//  und startet sie neu. Ohne Fremd-Framework.
//

import AppKit
import Foundation
import Observation
import Security

@Observable
final class Updater {
    static let shared = Updater()
    static let repository = "tpa339/eppur"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, download: URL)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    var automaticChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecks, forKey: "autoUpdateCheck")
            if automaticChecks { startAutomaticChecks() } else { loopTask?.cancel() }
        }
    }

    @ObservationIgnored private var loopTask: Task<Void, Never>?

    private init() {
        automaticChecks = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Dev-Builds (aus Xcode) aktualisieren sich nicht selbst.
    static var isSupported: Bool { !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev") }

    var availableVersion: String? {
        if case .available(let version, _) = state { return version }
        return nil
    }

    // MARK: - Suchen

    func startAutomaticChecks() {
        guard Self.isSupported, automaticChecks else { return }
        loopTask?.cancel()
        loopTask = Task {
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        let previous = state
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Eppur-Updater", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status != 404 else { throw UpdateError.message("Keine veröffentlichte Version gefunden") }
            guard status == 200 else { throw UpdateError.message("GitHub antwortet mit \(status)") }
            let release = try JSONDecoder().decode(Release.self, from: data)
            lastChecked = Date()
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(version, than: Self.currentVersion) else {
                state = .upToDate
                return
            }
            guard let asset = release.assets.first(where: { $0.name == "Eppur-\(version).zip" }) else {
                throw UpdateError.message("Version \(version) hat keine App-Datei")
            }
            state = .available(version: version, download: asset.browserDownloadURL)
            Diagnostics.log("Update verfügbar: \(version)")
        } catch is CancellationError {
            state = previous == .checking ? .idle : previous
        } catch let error as URLError where error.code == .cancelled {
            state = previous == .checking ? .idle : previous
        } catch {
            // Ein schon gefundenes Update bleibt angeboten, auch wenn eine spätere Suche scheitert.
            if case .available = previous {
                state = previous
            } else {
                state = .failed("Update-Suche: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Installieren

    func install() async {
        guard case .available(let version, let download) = state else { return }
        let target = Bundle.main.bundleURL
        guard !target.path.hasPrefix("/private/var/folders"),
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            state = .failed("Update: Eppur zuerst in den Ordner „Programme“ verschieben")
            return
        }
        state = .installing("Lade Version \(version) …")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("EppurUpdate-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let (downloaded, response) = try await URLSession.shared.download(from: download)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("Download fehlgeschlagen") }
            let zip = work.appendingPathComponent("Eppur.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            state = .installing("Prüfe Version \(version) …")
            let newApp = work.appendingPathComponent("unpacked/Eppur.app")
            // Entpacken und Signaturprüfung dauern – nicht im Main Thread.
            try await Task.detached {
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.appendingPathComponent("unpacked").path])
                try Self.verify(newApp: newApp)
                try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            }.value

            state = .installing("Starte neu …")
            try Self.replaceAndRelaunch(target: target, with: newApp)
            Diagnostics.log("Update auf \(version): App wird ersetzt und neu gestartet")
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed("Update: \(error.localizedDescription)")
        }
    }

    /// Gleiche Bundle-ID, neuere Version und eine gültige Signatur, die dieselbe
    /// Anforderung erfüllt wie die laufende App (gleiches Zertifikat).
    nonisolated private static func verify(newApp: URL) throws {
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.message("Heruntergeladene Datei ist keine Eppur-App")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard isNewer(version, than: current) else {
            throw UpdateError.message("Heruntergeladene Version \(version) ist nicht neuer")
        }

        var me: SecCode?
        var myStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &myStatic) == errSecSuccess, let myStatic,
              SecCodeCopyDesignatedRequirement(myStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(newApp as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            throw UpdateError.message("Signatur lässt sich nicht prüfen")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        guard status == errSecSuccess else {
            // Mit install.sh gebaute Apps tragen ein eigenes lokales Zertifikat.
            throw UpdateError.message("Signatur passt nicht zu dieser App (\(status)) – selbst gebaut? Dann mit install.sh aktualisieren")
        }
    }

    /// Ein kleines Skript wartet, bis Eppur beendet ist, tauscht die App aus und startet sie.
    /// Schlägt der Tausch fehl, bleibt die alte App erhalten.
    private static func replaceAndRelaunch(target: URL, with newApp: URL) throws {
        let script = """
        i=0
        while kill -0 "$1" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
        kill -0 "$1" 2>/dev/null && exit 1
        rm -rf "$2.old"
        if mv "$2" "$2.old"; then
          if mv "$3" "$2"; then rm -rf "$2.old"; else mv "$2.old" "$2"; fi
        fi
        open -n "$2"
        rm -rf "$4"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "eppur-update",
                             "\(ProcessInfo.processInfo.processIdentifier)", target.path, newApp.path,
                             newApp.deletingLastPathComponent().deletingLastPathComponent().path]
        try process.run()
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("\(URL(fileURLWithPath: tool).lastPathComponent) fehlgeschlagen (\(process.terminationStatus))")
        }
    }

    // MARK: - GitHub

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, browserDownloadURL = "browser_download_url" }
    }

    nonisolated private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): text }
        }
    }
}
