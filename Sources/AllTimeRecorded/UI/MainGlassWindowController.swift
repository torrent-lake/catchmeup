import AppKit
import SwiftUI

/// Hosts the main glass window.
///
/// As of Phase 2 we're back to hosting `MainDashboardView` (the calendar/
/// heatmap-centric layout inherited from AllTimeRecorded) as the primary
/// content. The on-demand agent chat lives in the floating `RecallPanelController`
/// overlay, not in the main window. This keeps the visual language the user
/// already likes (the pulsing heatmap, the calendar arcs, the day navigator)
/// and puts the LLM-powered Q&A behind a deliberate toggle rather than forcing
/// it to share the primary surface.
///
/// Construction still accepts `leannBridge` for future Phase 3 wiring that
/// will extend the dashboard with context-density overlays drawn from all
/// indexed sources, not just recording activity.
@MainActor
final class MainGlassWindowController: NSWindowController {
    private let appModel: AppModel
    private let calendarService: CalendarOverlayService
    private let modelAssetService: ModelAssetService
    private let recallController: RecallPanelController
    private let leannBridge: any LEANNBridging
    private let contextLoader: DayContextLoader
    private let onTranscribeNow: () -> Void

    init(
        appModel: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService,
        recallController: RecallPanelController,
        leannBridge: any LEANNBridging,
        contextLoader: DayContextLoader,
        onTranscribeNow: @escaping () -> Void
    ) {
        self.appModel = appModel
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService
        self.recallController = recallController
        self.leannBridge = leannBridge
        self.contextLoader = contextLoader
        self.onTranscribeNow = onTranscribeNow

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let recall = recallController
        let transcribeNow = onTranscribeNow
        let view = MainDashboardView(
            appModel: appModel,
            calendarService: calendarService,
            modelAssetService: modelAssetService,
            contextLoader: contextLoader,
            showsWindowControls: true,
            onCloseWindow: { window.performClose(nil) },
            onMinimizeWindow: { window.miniaturize(nil) },
            onZoomWindow: { window.performZoom(nil) },
            onToggleRecall: { recall.toggle() },
            onTranscribeNow: transcribeNow
        )
        let hosting = NSHostingController(rootView: view)
        window.title = "CatchMeUp"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 560, height: 320)
        window.contentViewController = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Match the original AllTimeRecorded content size — the heatmap
        // layout is tuned for 680×420.
        window.setContentSize(NSSize(width: 680, height: 420))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            recallController.hide()
        } else {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            recallController.show(besideWindow: window)
        }
    }
}
