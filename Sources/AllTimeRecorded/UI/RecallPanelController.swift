import AppKit
import SwiftUI

/// Hosts the floating agent chat panel beside the main glass window.
///
/// **Name note**: this class is still called `RecallPanelController` for
/// Phase 2 back-compat with existing call sites (StatusBarController and
/// MainDashboardView reference it). It no longer has anything to do with
/// the legacy "Recall Terminal" keyword-search view — its content is now
/// `AgentChatView` driven by an `AgentSession` + Claude. Rename to
/// `AgentChatPanelController` is scheduled for Phase 4 cleanup.
///
/// The window management (floating panel, positioning beside the main
/// window, toggle/show/hide) is inherited from the original controller
/// unchanged.
@MainActor
final class RecallPanelController {
    private let panel: AgentChatPanel
    private let viewModel: AgentChatViewModel
    private var lastOrigin: NSPoint?

    init(viewModel: AgentChatViewModel) {
        self.viewModel = viewModel

        let panel = AgentChatPanel(contentSize: NSSize(width: 380, height: 520))
        self.panel = panel

        let hosting = NSHostingController(
            rootView: AgentChatView(
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

        if let visibleFrame = screen?.visibleFrame {
            if origin.x + panelSize.width > visibleFrame.maxX {
                origin.x = mainFrame.minX - panelSize.width - gap
            }
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

/// Floating panel that hosts the agent chat. Identical window properties
/// to the legacy `RecallPanel` it replaces — floating, borderless-ish,
/// movable by background, no standard window buttons.
private final class AgentChatPanel: NSPanel {
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
        minSize = NSSize(width: 320, height: 400)

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
