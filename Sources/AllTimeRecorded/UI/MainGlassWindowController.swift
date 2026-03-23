import AppKit
import SwiftUI

@MainActor
final class MainGlassWindowController: NSWindowController {
    private let appModel: AppModel
    private let calendarService: CalendarOverlayService
    private let modelAssetService: ModelAssetService

    init(
        appModel: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService
    ) {
        self.appModel = appModel
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 390),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let view = MainDashboardView(
            appModel: appModel,
            calendarService: calendarService,
            modelAssetService: modelAssetService,
            showsWindowControls: true,
            onCloseWindow: { window.performClose(nil) },
            onMinimizeWindow: { window.miniaturize(nil) },
            onZoomWindow: { window.performZoom(nil) }
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
        } else {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
