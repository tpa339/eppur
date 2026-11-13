//
//  ScreenCapture.swift
//  Eppur
//
//  Fenster- und Bereichs-Screenshots über ScreenCaptureKit.
//  Alle Rechtecke in globalen CG-Koordinaten (Ursprung oben links am Hauptbildschirm).
//

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

enum CaptureTarget {
    case window(CGWindowID, CGRect)
    case region(CGRect)

    var rect: CGRect {
        switch self {
        case .window(_, let rect), .region(let rect): rect
        }
    }
}

enum CaptureError: LocalizedError {
    case windowNotFound
    case displayNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .windowNotFound: "Fenster nicht gefunden"
        case .displayNotFound: "Bildschirm nicht gefunden"
        case .saveFailed: "Screenshot konnte nicht gespeichert werden"
        }
    }
}

enum ScreenCapture {
    static func captureWindow(id: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func captureRegion(_ rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) })
                ?? content.displays.first(where: { $0.frame.intersects(rect) }) else {
            throw CaptureError.displayNotFound
        }
        // Eigene schwebende Ebenen (Notch, Auswahlrahmen) nicht mit aufnehmen –
        // das normale Eppur-Fenster (Ebene 0) aber schon.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let overlays = content.windows.filter { $0.owningApplication?.processID == ownPID && $0.windowLayer != 0 }
        let filter = SCContentFilter(display: display, excludingWindows: overlays)
        let scale = CGFloat(filter.pointPixelScale)

        let clipped = rect.intersection(display.frame)
        let local = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)

        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Int(local.width * scale)
        config.height = Int(local.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.saveFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.saveFailed }
    }

    /// Oberstes normales Fenster (Ebene 0) unter einem Punkt.
    static func windowUnder(_ point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        // Nur Ebene 0: eigene Overlays liegen höher, das Eppur-Hauptfenster lässt sich so auch aufnehmen.
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let number = info[kCGWindowNumber as String] as? Int,
                  bounds.width > 40, bounds.height > 40,
                  bounds.contains(point) else { continue }
            return (CGWindowID(number), bounds)
        }
        return nil
    }
}

/// Umrechnung zwischen Cocoa-Koordinaten (unten links) und CG-Koordinaten (oben links).
enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cgPoint(fromCocoa p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func cgRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cocoaRect(fromCG r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
