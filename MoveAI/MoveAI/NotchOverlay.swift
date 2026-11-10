//
//  NotchOverlay.swift
//  MoveAI
//
//  Schwarze „Insel“, die aus der Notch herauswächst und während der Aufnahme
//  eine laufende Waveform zeigt. Ohne Notch: gleiche Insel oben mittig.
//

import AppKit
import SwiftUI

struct NotchMetrics {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var wing: CGFloat = 70
    var bodyHeight: CGFloat = 36

    var expandedSize: CGSize {
        CGSize(width: notchWidth + 2 * wing, height: notchHeight + bodyHeight)
    }

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = top
        } else {
            notchWidth = 180
            notchHeight = NSStatusBar.system.thickness
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchOverlayController {
    private var panel: NotchPanel?
    private var screenObserver: Any?

    func install(controller: AppController) {
        place(controller: controller)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(controller: controller) }
        }
    }

    private func place(controller: AppController) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let metrics = NotchMetrics(screen: screen)
        let size = metrics.expandedSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = self.panel ?? NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: NotchView(controller: controller, metrics: metrics))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

struct NotchView: View {
    let controller: AppController
    let metrics: NotchMetrics

    private var isActive: Bool { controller.phase != .idle }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            content
                .frame(height: metrics.bodyHeight)
                .padding(.horizontal, 16)
                .opacity(isActive ? 1 : 0)
        }
        .frame(width: isActive ? metrics.expandedSize.width : metrics.notchWidth,
               height: isActive ? metrics.expandedSize.height : metrics.notchHeight)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: isActive ? 22 : 10,
                                          bottomTrailingRadius: isActive ? 22 : 10))
        .opacity(isActive ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: controller.phase)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)
            Group {
                switch controller.phase {
                case .recording, .idle:
                    WaveformView(levels: controller.levels)
                case .transcribing:
                    Text("Transkribiere …")
                case .done(let message):
                    Text(message)
                case .failed(let message):
                    Text(message)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            captureBadge
                .frame(width: 26)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.phase {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .phaseAnimator([1.0, 0.35]) { view, value in view.opacity(value) } animation: { _ in .easeInOut(duration: 0.6) }
        case .transcribing:
            ProgressView().controlSize(.small).tint(.white)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var captureBadge: some View {
        if controller.captureCount > 0, controller.phase == .recording || controller.phase == .transcribing {
            HStack(spacing: 2) {
                Image(systemName: "camera.fill")
                Text("\(controller.captureCount)")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        } else {
            Color.clear
        }
    }
}

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [.white, .white.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: max(3, levels[index] * 24))
            }
        }
        .frame(height: 26)
        .animation(.linear(duration: 0.06), value: levels)
    }
}
