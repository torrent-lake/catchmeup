import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let onQuit: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: 116)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "退出并停止留存",
            action: #selector(handleQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()

    init(model: AppModel, onQuit: @escaping () -> Void) {
        self.model = model
        self.onQuit = onQuit
        super.init()
        configureStatusItem()
        configurePopover()
        bindModel()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "AllTimeRecorded"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 448, height: 258)
        popover.contentViewController = NSHostingController(rootView: PopoverContentView(model: model))
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
        let image = StatusTimelineImageFactory.makeImage(bins: snapshot.bins, state: snapshot.state)
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.toolTip = "AllTimeRecorded · \(model.stateTitle)"
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(from: sender)
            return
        }

        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        togglePopover(from: sender)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
