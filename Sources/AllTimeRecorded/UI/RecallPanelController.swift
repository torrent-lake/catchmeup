import AppKit
import SwiftUI

@MainActor
final class RecallPanelController {
    private let panel: RecallPanel
    private let viewModel: RecallPanelViewModel
    private var lastOrigin: NSPoint?

    init(viewModel: RecallPanelViewModel) {
        self.viewModel = viewModel

        let panel = RecallPanel(contentSize: NSSize(width: 320, height: 440))
        self.panel = panel

        let hosting = NSHostingController(
            rootView: RecallPanelView(
                viewModel: viewModel,
                onClose: { [weak panel] in panel?.orderOut(nil) }
            )
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.isOpaque = false
        panel.contentViewController = hosting
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible {
            lastOrigin = panel.frame.origin
            panel.orderOut(nil)
        } else {
            if let origin = lastOrigin {
                panel.setFrameOrigin(origin)
            } else {
                positionDefault()
            }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func show() {
        guard !panel.isVisible else { return }
        toggle()
    }

    func show(besideWindow mainWindow: NSWindow) {
        guard !panel.isVisible else { return }
        positionBeside(mainWindow)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        lastOrigin = panel.frame.origin
        panel.orderOut(nil)
    }

    private func positionBeside(_ mainWindow: NSWindow) {
        let mainFrame = mainWindow.frame
        let panelSize = panel.frame.size
        let gap: CGFloat = 12
        let screen = mainWindow.screen ?? NSScreen.main

        var origin = NSPoint(
            x: mainFrame.maxX + gap,
            y: mainFrame.maxY - panelSize.height
        )

        // If no room on the right, place on the left
        if let visibleFrame = screen?.visibleFrame {
            if origin.x + panelSize.width > visibleFrame.maxX {
                origin.x = mainFrame.minX - panelSize.width - gap
            }
            // Clamp vertically
            origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height))
        }

        panel.setFrameOrigin(origin)
    }

    private func positionDefault() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.maxX - panelSize.width - 24,
            y: visibleFrame.maxY - panelSize.height - 80
        )
        panel.setFrameOrigin(origin)
    }
}

private final class RecallPanel: NSPanel {
    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            titlebarSeparatorStyle = .none
        }
        isMovableByWindowBackground = true
        minSize = NSSize(width: 280, height: 320)

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
