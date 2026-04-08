import AppKit
import Combine
import Foundation
import SwiftUI
#if canImport(ServiceManagement)
import ServiceManagement
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBarController: StatusBarController?
    private var sleepWakeMonitor: SleepWakeMonitor?
    private var recordingService: DefaultRecordingService?
    private var eventStore: EventStore?
    private var calendarOverlayService: CalendarOverlayService?
    private var modelAssetService: ModelAssetService?
    private var transcriptionOrchestrator: TranscriptionOrchestrator?
    private var recallPanelController: RecallPanelController?
    private var onboardingWindowController: NSWindowController?
    private var allowManualTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let paths = AppPaths()
            let store = try EventStore(paths: paths)
            let diskGuard = DefaultDiskGuardService(paths: paths)
            let powerAssertionService = IOKitPowerAssertionService()
            let calendarOverlay = CalendarOverlayService(
                store: CalendarSourcesStore(paths: paths),
                systemProvider: SystemCalendarProvider()
            )
            let modelAssets = ModelAssetService(paths: paths)
            let transcription = TranscriptionOrchestrator(
                paths: paths,
                modelService: modelAssets
            )

            let service = DefaultRecordingService(
                paths: paths,
                eventStore: store,
                powerAssertionService: powerAssertionService,
                diskGuardService: diskGuard
            )
            service.onSnapshot = { [weak self] snapshot in
                Task { @MainActor in
                    self?.model.apply(snapshot: snapshot)
                }
            }

            let sleepMonitor = SleepWakeMonitor()
            sleepMonitor.onWillSleep = { [weak service] in
                Task { @MainActor in
                    service?.handleWillSleep()
                }
            }
            sleepMonitor.onDidWake = { [weak service] in
                Task { @MainActor in
                    service?.handleDidWake()
                }
            }
            sleepMonitor.start()

            self.eventStore = store
            self.recordingService = service
            self.sleepWakeMonitor = sleepMonitor
            self.calendarOverlayService = calendarOverlay
            self.modelAssetService = modelAssets
            self.transcriptionOrchestrator = transcription

            let queryService = LocalTranscriptSearchService(paths: paths)
            let recallViewModel = RecallPanelViewModel(queryService: queryService)
            let recallController = RecallPanelController(viewModel: recallViewModel)
            self.recallPanelController = recallController

            // Sync highlights from Recall panel to AppModel
            recallViewModel.$highlightedTimeRanges
                .receive(on: RunLoop.main)
                .assign(to: &model.$highlightedTimeRanges)

            statusBarController = StatusBarController(
                model: model,
                calendarService: calendarOverlay,
                modelAssetService: modelAssets,
                recallController: recallController,
                onTranscribeNow: { [weak transcription] in
                    Task { @MainActor in
                        await transcription?.forceTranscribeAll()
                    }
                }
            ) { [weak self] in
                self?.manualQuit()
            }

            registerLoginItemIfPossible()

            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboarding()
            } else {
                requestMicrophoneThenStart()
            }

            transcription.start()
        } catch {
            model.setState(.recovering)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingService?.stop(reason: .userQuit)
        sleepWakeMonitor?.stop()
        transcriptionOrchestrator?.stop()
        eventStore?.markCleanShutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowManualTermination ? .terminateNow : .terminateCancel
    }

    private func requestMicrophoneThenStart() {
        MicrophonePermissionManager.request { [weak self] granted in
            guard let self else { return }
            if granted {
                self.recordingService?.start()
            } else {
                self.model.setState(.blockedNoPermission)
            }
        }
    }

    @objc private func manualQuit() {
        allowManualTermination = true
        recordingService?.stop(reason: .userQuit)
        sleepWakeMonitor?.stop()
        transcriptionOrchestrator?.stop()
        eventStore?.markCleanShutdown()
        NSApp.terminate(nil)
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        let view = OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            window.orderOut(nil)
            self?.onboardingWindowController = nil
            self?.requestMicrophoneThenStart()
        }
        let hosting = NSHostingController(rootView: view)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hosting
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindowController = controller
    }

    private func registerLoginItemIfPossible() {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // Ignore in unsigned/dev runs.
            }
        }
        #endif
    }
}
