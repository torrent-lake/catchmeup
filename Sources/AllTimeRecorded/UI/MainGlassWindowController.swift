import AppKit
import SwiftUI

/// Hosts the main glass window. Phase 1 pivot: the primary content is now
/// `BriefingDashboardView` (CatchMeUp's new identity), not `MainDashboardView`
/// (the recording-centric heatmap from AllTimeRecorded).
///
/// The constructor still accepts the old set of dependencies so that
/// `StatusBarController` can keep its call signature intact; the refs for
/// `calendarService`, `modelAssetService`, `recallController`, and
/// `onTranscribeNow` are stored for Phase 2+ reuse (pre-meeting briefs,
/// agent chat, transcription controls).
@MainActor
final class MainGlassWindowController: NSWindowController {
    private let appModel: AppModel
    private let calendarService: CalendarOverlayService
    private let modelAssetService: ModelAssetService
    private let recallController: RecallPanelController
    private let leannBridge: any LEANNBridging
    private let onTranscribeNow: () -> Void

    init(
        appModel: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService,
        recallController: RecallPanelController,
        leannBridge: any LEANNBridging,
        onTranscribeNow: @escaping () -> Void
    ) {
        self.appModel = appModel
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService
        self.recallController = recallController
        self.leannBridge = leannBridge
        self.onTranscribeNow = onTranscribeNow

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let recall = recallController
        let view = BriefingDashboardView(
            appModel: appModel,
            showsWindowControls: true,
            onCloseWindow: { window.performClose(nil) },
            onMinimizeWindow: { window.miniaturize(nil) },
            onZoomWindow: { window.performZoom(nil) },
            onToggleRecall: { recall.toggle() }
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
        window.minSize = NSSize(width: 560, height: 380)
        window.contentViewController = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.setContentSize(NSSize(width: 680, height: 520))
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
