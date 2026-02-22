import AppKit
import SwiftUI

@MainActor
final class TranscriptionOverlayWindow {
    private var panel: NSPanel?

    func show(appState: AppState) {
        if let existing = panel {
            existing.orderFront(nil)
            return
        }

        let overlayView = TranscriptionOverlayView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 80)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.hidesOnDeactivate = false

        positionPanel(panel)
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func hideAfterDelay(_ seconds: TimeInterval = 1.5) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            hide()
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.minY + 100

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
