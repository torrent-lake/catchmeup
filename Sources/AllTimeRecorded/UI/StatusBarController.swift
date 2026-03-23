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
    private let onQuit: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = OverlayPanel(contentSize: NSSize(width: 448, height: 258))
    private let styleMenuItem = NSMenuItem(title: "切换样式", action: #selector(handleCycleStyle), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(title: "退出并停止留存", action: #selector(handleQuit), keyEquivalent: "")
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var currentStyle: StatusIconStyle
    private var lastSnapshot: RecordingSnapshot = .empty()
    private lazy var mainWindowController = MainGlassWindowController(
        appModel: model,
        calendarService: calendarService,
        modelAssetService: modelAssetService
    )
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        styleMenuItem.target = self
        menu.addItem(styleMenuItem)
        menu.addItem(.separator())
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        return menu
    }()

    init(
        model: AppModel,
        calendarService: CalendarOverlayService,
        modelAssetService: ModelAssetService,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.calendarService = calendarService
        self.modelAssetService = modelAssetService
        self.onQuit = onQuit
        self.currentStyle = StatusBarController.loadStyle()
        super.init()
        configureStatusItem()
        configurePanel()
        bindModel()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.length = currentStyle.statusItemLength
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "AllTimeRecorded"
    }

    private func configurePanel() {
        let hosting = NSHostingController(
            rootView: PopoverContentView(
                model: model,
                onOpenMainWindow: { [weak self] in
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
    }

    private func apply(snapshot: RecordingSnapshot) {
        lastSnapshot = snapshot
        renderCurrentIcon()
        statusItem.button?.toolTip = "AllTimeRecorded · \(model.stateTitle)"
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

    @objc private func handleQuit() {
        hidePanel()
        onQuit()
    }

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
