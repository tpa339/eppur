//
//  Clipboard.swift
//  Eppur
//
//  Schreibt Transkript und Screenshots gleichzeitig in die Zwischenablage:
//  Eintrag 1 trägt Text UND PNG (Cmd+V im Terminal → Text, Ctrl+V in
//  Claude Code → Bild). Weitere Bilder folgen als eigene Einträge,
//  ihre Pfade stehen zusätzlich im Text.
//

import AppKit

enum ClipboardWriter {
    static func compose(transcript: String, images: [URL], appendPaths: Bool) -> String {
        guard appendPaths, !images.isEmpty else { return transcript }
        let lines = images.enumerated().map { index, url in "[Screenshot \(index + 1): \(url.path)]" }
        let paths = lines.joined(separator: "\n")
        return transcript.isEmpty ? paths : "\(transcript)\n\n\(paths)"
    }

    static func write(text: String, images: [URL], mode: ClipboardMode) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setString(text, forType: .string)
        var items = [first]

        if mode == .textAndImage {
            for (index, url) in images.enumerated() {
                guard let png = try? Data(contentsOf: url) else { continue }
                let item = index == 0 ? first : NSPasteboardItem()
                item.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation {
                    item.setData(tiff, forType: .tiff)
                }
                if index > 0 { items.append(item) }
            }
        }
        pasteboard.writeObjects(items)
    }
}
