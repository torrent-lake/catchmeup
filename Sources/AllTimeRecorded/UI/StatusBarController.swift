import AppKit
import Combine
import SwiftUI

private final class OverlayPanel: NSPanel {
    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusBarController: NSObject {
    private enum Preferences {
        static let iconStyleKey = "statusIconStyle"
    }

    private let model: AppModel
    private let calendarService: CalendarOverlayService
    private let modelAssetService: ModelAssetService
    private let recallController: RecallPanelController
    private let leannBridge: any LEANNBridging
    private let onQuit: () -> Void
    private let onTranscribeNow: () -> Void
    private let onRecordingModeChanged: (RecordingMode) -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = OverlayPanel(contentSize: NSSize(width: 448, height: 258))
    private let modeGentleMenuItem = NSMenuItem(
        title: "Recording: Gentle",
        action: #selector(handleSelectGentleMode),
        keyEquivalent: ""
    )
    private let modeManualMenuItem = NSMenuItem(
        title: "Recording: Manual",
        action: #selector(handleSelectManualMode),
        keyEquivalent: ""
    )
    private let modeRogueMenuItem = NSMenuItem(
        title: "Recording: Rogue",
        action: #selector(handleSelectRogueMode),
        keyEquivalent: ""
    )
    private let styleMenuItem = NSMenuItem(title: "切换样式", action: #selector(handleCycleStyle), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(title: "退出并停止留存", action: #selector(handleQuit), keyEquivalent: "")
#if DEBUG
    private let debugLeannProbeMenuItem = NSMenuItem(
        title: "Debug: Probe LEANN (mail_index, \"hello\")",
        action: #selector(handleDebugLeannProbe),
        keyEquivalent: ""
    )
#endif
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var currentStyle: StatusIconStyle
    private var lastSnapshot: RecordingSnapshot = .empty()
    private lazy var mainWindowController = MainGlassWindowController(
        appModel: model,
        calendarService: calendarService,
        modelAssetService: modelAssetService,
        recallController: recallController,
        leannBridge: leannBridge,
        onTranscribeNow: onTranscribeNow
    )
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        modeGentleMenuItem.target = self
        modeManualMenuItem.target = self
        modeRogueMenuItem.target = self
        menu.addItem(modeGentleMenuItem)
        menu.addItem(modeManualMenuItem)
        menu.addItem(modeRogueMenuItem)
        menu.addItem(.separator())
        styleMenuItem.target = self
        menu.addItem(styleMenuItem)
#if DEBUG
        debugLeannProbeMenuItem.target = self
        menu.addItem(.separator())
        menu.addItem(debugLeannProbeMenuItem)
#endif
        menu.addItem(.separator())
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        return menu
    }()

    init(
        model: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService,
        recallController: RecallPanelController,
        leannBridge: any LEANNBridging,
        onTranscribeNow: @escaping () -> Void,
        onRecordingModeChanged: @escaping (RecordingMode) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService
        self.recallController = recallController
        self.leannBridge = leannBridge
        self.onTranscribeNow = onTranscribeNow
        self.onRecordingModeChanged = onRecordingModeChanged
        self.onQuit = onQuit
        self.currentStyle = StatusBarController.loadStyle()
        super.init()
        configureStatusItem()
        configurePanel()
        bindModel()
        syncModeMenuCheckmarks(model.recordingMode)
    }

    /// Opens the main window programmatically (used by AppDelegate on launch to
    /// reveal the new briefing dashboard identity).
    func openMainWindow() {
        let window = mainWindowController.window
        if window?.isVisible == true {
            return
        }
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindowController.window {
            recallController.show(besideWindow: w)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = currentStyle.statusItemLength
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "CatchMeUp"
    }

    private func configurePanel() {
        let hosting = NSHostingController(
            rootView: PopoverContentView(
                model: model,
                onOpenMainWindow: { [weak self] in
                    try? "[ATR-popover] tapped \(Date())\n".data(using: .utf8)?.write(to: URL(fileURLWithPath: "/tmp/atr-debug.log"), options: .atomic)
                    self?.toggleMainWindow()
                }
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

    private func bindModel() {
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.apply(snapshot: snapshot)
            }
            .store(in: &cancellables)

        model.$recordingMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.syncModeMenuCheckmarks(mode)
            }
            .store(in: &cancellables)
    }

    private func apply(snapshot: RecordingSnapshot) {
        lastSnapshot = snapshot
        renderCurrentIcon()
        statusItem.button?.toolTip = "CatchMeUp · \(model.stateTitle)"
    }

    private func syncModeMenuCheckmarks(_ mode: RecordingMode) {
        modeGentleMenuItem.state = (mode == .gentle) ? .on : .off
        modeManualMenuItem.state = (mode == .manual) ? .on : .off
        modeRogueMenuItem.state = (mode == .rogue)  ? .on : .off
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel(from: sender)
            return
        }

        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            hidePanel()
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        togglePanel(from: sender)
    }

    private func togglePanel(from button: NSStatusBarButton) {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel(from: button)
        }
    }

    private func showPanel(from button: NSStatusBarButton) {
        positionPanel(relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installPanelEventMonitors(statusButton: button)
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        stopPanelEventMonitors()
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let panelSize = panel.frame.size
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buttonFrameInScreen.insetBy(dx: -500, dy: -500)
        let margin: CGFloat = 8

        var origin = NSPoint(
            x: buttonFrameInScreen.midX - (panelSize.width / 2),
            y: buttonFrameInScreen.minY - panelSize.height - margin
        )
        origin.x = min(max(origin.x, screenFrame.minX + margin), screenFrame.maxX - panelSize.width - margin)
        origin.y = max(screenFrame.minY + margin, origin.y)
        panel.setFrameOrigin(origin)
        panel.invalidateShadow()
    }

    private func installPanelEventMonitors(statusButton: NSStatusBarButton) {
        stopPanelEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hidePanel()
                return nil
            }
            guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
                return event
            }
            if event.window == self.panel {
                return event
            }
            if event.window == statusButton.window {
                return event
            }
            self.hidePanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hidePanel()
            }
        }
    }

    private func stopPanelEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    @objc private func handleCycleStyle() {
        currentStyle = currentStyle.next
        saveStyle(currentStyle)
        statusItem.length = currentStyle.statusItemLength
        renderCurrentIcon()
    }

    @objc private func handleSelectGentleMode() {
        onRecordingModeChanged(.gentle)
    }

    @objc private func handleSelectManualMode() {
        onRecordingModeChanged(.manual)
    }

    @objc private func handleSelectRogueMode() {
        onRecordingModeChanged(.rogue)
    }

    @objc private func handleQuit() {
        hidePanel()
        onQuit()
    }

#if DEBUG
    @objc private func handleDebugLeannProbe() {
        let bridge = leannBridge
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "LEANN probe: mail_index"
            alert.informativeText = "Running…"
            do {
                let raw = try await bridge.searchRaw(index: "mail_index", query: "hello", topK: 5)
                let chunks = try await bridge.search(index: "mail_index", query: "hello", topK: 5)
                alert.messageText = "LEANN probe OK — \(chunks.count) chunks"
                alert.informativeText = String(raw.prefix(2000))
                alert.alertStyle = .informational
            } catch {
                alert.messageText = "LEANN probe failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
            }
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }
#endif

    private func renderCurrentIcon() {
        let image = StatusTimelineImageFactory.makeImage(
            bins: lastSnapshot.bins,
            state: lastSnapshot.state,
            style: currentStyle
        )
        image.isTemplate = false
        statusItem.button?.image = image
    }

    private func toggleMainWindow() {
        let msg = "[ATR] toggleMainWindow called at \(Date())\n"
        let logURL = AppPaths().metaRoot.appendingPathComponent("debug.log")
        if let data = msg.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fh = try? FileHandle(forWritingTo: logURL) {
                    fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
        mainWindowController.toggle()
    }

    private static func loadStyle() -> StatusIconStyle {
        let raw = UserDefaults.standard.string(forKey: Preferences.iconStyleKey) ?? ""
        return StatusIconStyle(rawValue: raw) ?? .longStrip
    }

    private func saveStyle(_ style: StatusIconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: Preferences.iconStyleKey)
    }
}
