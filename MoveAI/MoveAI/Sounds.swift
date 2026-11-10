//
//  Sounds.swift
//  MoveAI
//
//  Akustische Rückmeldung für Aufnahme-Start und -Ende.
//  Die Klänge werden synthetisch erzeugt (weiche Sinus-Zweiklänge),
//  damit sie dezent sind und nicht wie System-Warntöne klingen.
//

import AppKit

enum SoundStyle: String, CaseIterable, Identifiable {
    case soft      // weicher Zweiklang, aufsteigend / absteigend
    case bubble    // kurzer, runder „Tropfen“
    case chime     // heller Glockenklang mit Nachklang
    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Sanft"
        case .bubble: "Tropfen"
        case .chime: "Glocke"
        }
    }
}

enum Sounds {
    static func recordingStarted(_ style: SoundStyle) { play(style, rising: true) }
    static func recordingStopped(_ style: SoundStyle) { play(style, rising: false) }

    private static var cache: [String: NSSound] = [:]

    private static func play(_ style: SoundStyle, rising: Bool) {
        let key = "\(style.rawValue)-\(rising)"
        let sound = cache[key] ?? NSSound(data: render(style, rising: rising))
        guard let sound else { return }
        cache[key] = sound
        sound.stop()
        sound.play()
    }

    // MARK: - Synthese

    private struct Note {
        var frequency: Double
        var start: Double      // Sekunden
        var length: Double     // Sekunden bis zum Ausklingen
        var gain: Double
    }

    private static func notes(_ style: SoundStyle, rising: Bool) -> [Note] {
        switch style {
        case .soft:
            // Quinte: E5 → H5 (Start) bzw. H5 → E5 (Ende)
            let (a, b) = rising ? (659.3, 987.8) : (987.8, 659.3)
            return [Note(frequency: a, start: 0, length: 0.16, gain: 0.22),
                    Note(frequency: b, start: 0.075, length: 0.22, gain: 0.20)]
        case .bubble:
            // Kurzer Glissando-Effekt über drei nahe Töne
            let base = rising ? [523.3, 659.3, 784.0] : [784.0, 659.3, 523.3]
            return base.enumerated().map { i, f in
                Note(frequency: f, start: Double(i) * 0.035, length: 0.09, gain: 0.16)
            }
        case .chime:
            let f = rising ? 1318.5 : 987.8
            return [Note(frequency: f, start: 0, length: 0.45, gain: 0.16),
                    Note(frequency: f * 2.0, start: 0, length: 0.25, gain: 0.04)]
        }
    }

    private static func render(_ style: SoundStyle, rising: Bool) -> Data {
        let sampleRate = 44_100.0
        let parts = notes(style, rising: rising)
        let total = (parts.map { $0.start + $0.length }.max() ?? 0.3) + 0.02
        let count = Int(total * sampleRate)
        var samples = [Double](repeating: 0, count: count)

        for note in parts {
            let begin = Int(note.start * sampleRate)
            let length = Int(note.length * sampleRate)
            let attack = 0.006 * sampleRate
            for n in 0..<length where begin + n < count {
                let t = Double(n) / sampleRate
                let env = min(1, Double(n) / attack) * exp(-t * 5.5 / note.length)
                let tone = sin(2 * .pi * note.frequency * t) + 0.18 * sin(4 * .pi * note.frequency * t)
                samples[begin + n] += note.gain * env * tone
            }
        }
        return wav(samples, sampleRate: Int(sampleRate))
    }

    /// 16-Bit-Mono-WAV im Speicher.
    private static func wav(_ samples: [Double], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for s in samples {
            append(Int16(max(-1, min(1, s)) * Double(Int16.max)))
        }
        return data
    }
}
