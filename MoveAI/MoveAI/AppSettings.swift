//
//  AppSettings.swift
//  MoveAI
//
//  Einstellungen (UserDefaults) + API-Schlüssel im Schlüsselbund.
//

import Foundation
import Observation
import Security

enum EngineKind: String, CaseIterable, Identifiable {
    case local
    case api
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: "Eppur lokal (Parakeet)"
        case .api: "Eigene API (OpenAI-kompatibel)"
        }
    }
}

enum ClipboardMode: String, CaseIterable, Identifiable {
    /// Ein Eintrag mit Text **und** Bild (PNG) parallel.
    case textAndImage
    /// Nur Text (Bildpfade im Text).
    case textOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .textAndImage: "Text + Bild parallel"
        case .textOnly: "Nur Text (mit Bildpfaden)"
        }
    }
}

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var engine: EngineKind {
        didSet { defaults.set(engine.rawValue, forKey: "engine") }
    }
    var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }
    var apiBaseURL: String {
        didSet { defaults.set(apiBaseURL, forKey: "apiBaseURL") }
    }
    var apiModel: String {
        didSet { defaults.set(apiModel, forKey: "apiModel") }
    }
    var appendImagePaths: Bool {
        didSet { defaults.set(appendImagePaths, forKey: "appendImagePaths") }
    }
    var clipboardMode: ClipboardMode {
        didSet { defaults.set(clipboardMode.rawValue, forKey: "clipboardMode") }
    }
    var apiKey: String {
        didSet { Keychain.set(apiKey, account: "apiKey") }
    }
    /// Qwen-Nachkorrektur (nur lokale Engine).
    var correction: Bool {
        didSet { defaults.set(correction, forKey: "correction") }
    }
    /// Text automatisch ins aktive Textfeld einfügen.
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: "autoPaste") }
    }
    /// Töne bei Start und Ende der Aufnahme.
    var sounds: Bool {
        didSet { defaults.set(sounds, forKey: "sounds") }
    }
    var soundStyle: SoundStyle {
        didSet { defaults.set(soundStyle.rawValue, forKey: "soundStyle") }
    }
    /// Während der Aufnahme: Klick auf ein Fenster nimmt es auf.
    var captureWindowOnClick: Bool {
        didSet { defaults.set(captureWindowOnClick, forKey: "captureWindowOnClick") }
    }
    /// Während der Aufnahme: Ziehen markiert einen Bereich und nimmt ihn auf.
    var captureRegionOnDrag: Bool {
        didSet { defaults.set(captureRegionOnDrag, forKey: "captureRegionOnDrag") }
    }

    init() {
        engine = EngineKind(rawValue: defaults.string(forKey: "engine") ?? "") ?? .local
        correction = defaults.object(forKey: "correction") as? Bool ?? true
        autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        sounds = defaults.object(forKey: "sounds") as? Bool ?? true
        soundStyle = SoundStyle(rawValue: defaults.string(forKey: "soundStyle") ?? "") ?? .soft
        captureWindowOnClick = defaults.object(forKey: "captureWindowOnClick") as? Bool ?? true
        captureRegionOnDrag = defaults.object(forKey: "captureRegionOnDrag") as? Bool ?? true
        language = defaults.string(forKey: "language") ?? "de-DE"
        apiBaseURL = defaults.string(forKey: "apiBaseURL") ?? "http://localhost:8000/v1"
        apiModel = defaults.string(forKey: "apiModel") ?? "whisper-1"
        appendImagePaths = defaults.object(forKey: "appendImagePaths") as? Bool ?? true
        clipboardMode = ClipboardMode(rawValue: defaults.string(forKey: "clipboardMode") ?? "") ?? .textAndImage
        apiKey = Keychain.get(account: "apiKey") ?? ""
    }

    func makeEngine() -> any TranscriptionEngine {
        switch engine {
        case .local:
            MoveAIServiceEngine(correct: correction)
        case .api:
            OpenAICompatibleEngine(baseURL: apiBaseURL, model: apiModel, apiKey: apiKey)
        }
    }
}

/// Wortliste für Namen und Fachbegriffe – eine Zeile pro Eintrag.
/// Der MoveAI-Dienst liest dieselbe Datei bei jeder Korrektur.
enum Vocabulary {
    static var fileURL: URL { Storage.baseDirectory.appendingPathComponent("vocabulary.txt") }

    static func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8))
            ?? "# Eine Zeile pro Name oder Fachbegriff, z. B.\n# Claude Code\n# Parakeet\n"
    }

    static func save(_ text: String) {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

enum Keychain {
    private static let service = "local.moveai.MoveAI"

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
