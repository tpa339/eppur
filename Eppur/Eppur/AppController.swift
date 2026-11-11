//
//  AppController.swift
//  Eppur
//
//  Zentrale Ablaufsteuerung: Fn gedrückt → Aufnahme + Screenshot-Modus,
//  Fn losgelassen → Transkription → Zwischenablage + Verlauf.
//

import AppKit
import Observation

@Observable
final class AppController {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case done(String)
        case failed(String)
    }

    static let levelCount = 28

    private(set) var phase: Phase = .idle
    private(set) var levels: [CGFloat] = Array(repeating: 0, count: AppController.levelCount)
    private(set) var captureCount = 0

    let settings: AppSettings
    let history: HistoryStore
    let files: FileTranscriber

    @ObservationIgnored private let fnMonitor = FnKeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let notch = NotchOverlayController()
    @ObservationIgnored private let captureOverlay = CaptureOverlayController()

    @ObservationIgnored private var sessionDir: URL?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var captures: [URL] = []
    @ObservationIgnored private var captureTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotBlocked = false

    /// Kürzere Aufnahmen ohne Screenshot gelten als versehentlicher Fn-Druck.
    private let minimumDuration: TimeInterval = 0.35

    init() {
        let settings = AppSettings()
        let history = HistoryStore()
        self.settings = settings
        self.history = history
        files = FileTranscriber(history: history, settings: settings)
    }

    func start() {
        Diagnostics.logStartup()
        notch.install(controller: self)

        fnMonitor.onFnDown = { [weak self] in self?.beginRecording() }
        fnMonitor.onFnUp = { [weak self] in self?.finishRecording() }
        fnMonitor.onOtherKeyWhileFn = { [weak self] in self?.cancelRecording() }
        fnMonitor.start()

        captureOverlay.onCapture = { [weak self] target in self?.handleCapture(target) }

        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.pushLevel(CGFloat(level)) }
        }

        // Keine Systemdialoge beim Start – fehlende Freigaben zeigt das Einrichtungsfenster.
        if settings.engine == .local { EppurService.shared.startMonitoring() }
    }

    // MARK: - Aufnahme

    private func beginRecording() {
        switch phase {
        case .recording, .transcribing: return
        default: break
        }
        resetTask?.cancel()

        do {
            let dir = try Storage.newSessionDirectory()
            let audio = dir.appendingPathComponent("audio.wav")
            try recorder.start(writingTo: audio)
            sessionDir = dir
            audioURL = audio
        } catch {
            show(.failed("Mikrofon: \(error.localizedDescription)"))
            return
        }

        captures = []
        captureTasks = []
        captureCount = 0
        screenshotBlocked = false
        levels = Array(repeating: 0, count: Self.levelCount)
        startedAt = Date()
        phase = .recording
        if settings.captureWindowOnClick || settings.captureRegionOnDrag {
            captureOverlay.show(windowClick: settings.captureWindowOnClick, regionDrag: settings.captureRegionOnDrag)
        }
        if settings.sounds { Sounds.recordingStarted(settings.soundStyle) }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        recorder.stop()
        captureOverlay.hide()
        captureTasks.forEach { $0.cancel() }
        if let sessionDir { try? FileManager.default.removeItem(at: sessionDir) }
        sessionDir = nil
        phase = .idle
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        recorder.stop()
        captureOverlay.hide()

        let duration = Date().timeIntervalSince(startedAt ?? Date())
        // Kein Ton bei versehentlichem Antippen (wird gleich verworfen).
        if settings.sounds && (duration >= minimumDuration || !captureTasks.isEmpty) { Sounds.recordingStopped(settings.soundStyle) }
        if duration < minimumDuration && captureTasks.isEmpty {
            cancelRecording()
            phase = .idle
            return
        }

        phase = .transcribing
        let pending = captureTasks
        let audio = audioURL
        let engine = settings.makeEngine()
        let language = settings.language

        Task {
            for task in pending { await task.value }
            var result = TranscriptionResult(text: "")
            var errorText: String?
            if let audio, duration >= minimumDuration {
                do {
                    result = try await engine.transcribe(fileURL: audio, language: language)
                } catch {
                    errorText = error.localizedDescription
                }
            }
            deliver(result: result, duration: duration, engineName: engine.displayName, error: errorText)
        }
    }

    private func deliver(result: TranscriptionResult, duration: TimeInterval, engineName: String, error: String?) {
        let text = result.text
        let images = captures.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty && images.isEmpty {
            show(.failed(error ?? "Nichts erkannt"))
            return
        }

        let output = ClipboardWriter.compose(
            transcript: trimmed,
            images: images,
            appendPaths: settings.appendImagePaths
        )
        ClipboardWriter.write(text: output, images: images, mode: settings.clipboardMode)
        let pasted = settings.autoPaste && AutoPaste.paste()
        let missingAccessibility = settings.autoPaste && !Permissions.accessibility
        Diagnostics.log("Diktat fertig autoPaste=\(settings.autoPaste) pasted=\(pasted) images=\(images.count) screenshotBlocked=\(screenshotBlocked) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?") \(Diagnostics.permissionSummary())")

        history.add(TranscriptEntry(
            text: trimmed,
            rawText: result.rawText,
            imagePaths: images.map(\.path),
            audioPath: audioURL?.path,
            engine: engineName,
            duration: duration,
            error: error ?? result.note
        ))

        if let error, trimmed.isEmpty {
            show(.failed("Nur Bild kopiert – \(error)"))
        } else if missingAccessibility {
            show(.failed("Kopiert – Einfügen braucht Bedienungshilfen"))
        } else if screenshotBlocked {
            show(.failed("Text kopiert – Bildschirmaufnahme nicht freigegeben"))
        } else {
            let suffix = images.isEmpty ? "" : " + \(images.count) Bild\(images.count == 1 ? "" : "er")"
            show(.done((pasted ? "Eingefügt" : "In Zwischenablage") + suffix))
        }
    }

    private func show(_ newPhase: Phase) {
        phase = newPhase
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(newPhase == .idle ? 0 : 2.2))
            guard !Task.isCancelled else { return }
            if self.phase == newPhase { self.phase = .idle }
        }
    }

    // MARK: - Screenshots

    private func handleCapture(_ target: CaptureTarget) {
        guard phase == .recording, let dir = sessionDir else { return }
        // Ohne Freigabe würde jeder Versuch den Systemdialog erneut auslösen.
        guard Permissions.screenRecording else {
            Diagnostics.log("Screenshot blockiert: Bildschirmaufnahme nicht freigegeben")
            Permissions.requestScreenRecording()
            captureOverlay.hide()
            screenshotBlocked = true
            return
        }
        captureCount += 1
        let index = captureCount
        let url = dir.appendingPathComponent("screenshot-\(index).png")

        let task = Task {
            do {
                let image: CGImage
                switch target {
                case .window(let id, _):
                    image = try await ScreenCapture.captureWindow(id: id)
                case .region(let rect):
                    image = try await ScreenCapture.captureRegion(rect)
                }
                try ScreenCapture.savePNG(image, to: url)
                self.captures.append(url)
            } catch {
                self.captureCount -= 1
                NSLog("Eppur capture failed: \(error)")
            }
        }
        captureTasks.append(task)
        captureOverlay.flash(target.rect)
    }

    // MARK: - Pegel

    private func pushLevel(_ level: CGFloat) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }
}
