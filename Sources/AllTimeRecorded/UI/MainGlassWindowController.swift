import AppKit
import SwiftUI

@MainActor
final class MainGlassWindowController: NSWindowController {
    private let appModel: AppModel
    private let calendarService: CalendarOverlayService
    private let modelAssetService: ModelAssetService
    private let recallController: RecallPanelController
    private let onTranscribeNow: () -> Void

    init(
        appModel: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService,
        recallController: RecallPanelController,
        onTranscribeNow: @escaping () -> Void
    ) {
        self.appModel = appModel
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService
        self.recallController = recallController
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
            showsWindowControls: true,
            onCloseWindow: { window.performClose(nil) },
            onMinimizeWindow: { window.miniaturize(nil) },
            onZoomWindow: { window.performZoom(nil) },
            onToggleRecall: { recall.toggle() },
            onTranscribeNow: transcribeNow
        )
        let hosting = NSHostingController(rootView: view)
        window.title = "AllTimeRecorded"
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

        // Force the frame size after NSHostingController has been set,
        // since it overrides contentRect with the SwiftUI intrinsic size.
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
