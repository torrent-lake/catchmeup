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
    private var leannBridge: LEANNBridge?
    private var recordingPolicy: (any RecordingPolicy)?
    private var meetingTriggerWatcher: MeetingTriggerWatcher?
    private var digestScheduler: DigestScheduler?
    private var auditLog: AuditLog?
    private var allowManualTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let paths = AppPaths()
            try paths.ensureBaseDirectories()
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

            // Phase 1: instantiate the LEANN bridge. No calls yet — the dev
            // "Test LEANN" button in BriefingDashboardView drives the first one.
            let leann = LEANNBridge()
            self.leannBridge = leann

            self.eventStore = store
            self.recordingService = service
            self.sleepWakeMonitor = sleepMonitor
            self.calendarOverlayService = calendarOverlay
            self.modelAssetService = modelAssets
            self.transcriptionOrchestrator = transcription

            // Multi-source RAG wiring: all data sources are created at launch
            // and passed to CrossRefEngine. Sources that fail (e.g. no permission)
            // gracefully return empty results.
            let anthropic = AnthropicClient()
            let crossRef = CrossRefEngine()
            let audit = AuditLog(fileURL: paths.auditFileURL)
            self.auditLog = audit

            // Data sources: system-level macOS integration + LEANN indices
            let mailSource = MailDataSource(bridge: leann)
            let wechatSource = WeChatDataSource(bridge: leann)
            let wechatRecentSource = WeChatDataSource(
                bridge: leann,
                indexName: "wechat_recent"
            )
            let calendarSource = CalendarDataSource()
            let remindersSource = RemindersDataSource()
            let fileSource = FileDataSource(bridge: leann)
            let transcriptSource = TranscriptDataSource(bridge: leann)
            let imessageSource = IMessageDataSource()
            let photosSource = PhotosOCRDataSource()

            let allSources: [any DataSource] = [
                mailSource,
                wechatSource,
                wechatRecentSource,
                calendarSource,
                remindersSource,
                fileSource,
                transcriptSource,
                imessageSource,
                photosSource,
            ]

            let agentSession = AgentSession(
                llm: anthropic,
                crossRef: crossRef,
                defaultSources: allSources
            )

            let briefing = BriefingService(
                llm: anthropic,
                crossRef: crossRef,
                sources: allSources,
                paths: paths
            )

            let agentChatViewModel = AgentChatViewModel(
                session: agentSession,
                auditLog: audit,
                briefingService: briefing
            )
            let recallController = RecallPanelController(viewModel: agentChatViewModel)

            let contextLoader = DayContextLoader(sources: allSources)
            contextLoader.loadDay(Date())  // Pre-load today's context

            // Meeting trigger watcher + daily digest scheduler
            let meetingWatcher = MeetingTriggerWatcher(
                calendarService: calendarOverlay,
                briefingService: briefing
            )
            meetingWatcher.start()
            self.meetingTriggerWatcher = meetingWatcher

            let digest = DigestScheduler(briefingService: briefing)
            digest.start()
            self.digestScheduler = digest
            self.recallPanelController = recallController

            let controller = StatusBarController(
                model: model,
                calendarService: calendarOverlay,
                modelAssetService: modelAssets,
                recallController: recallController,
                leannBridge: leann,
                contextLoader: contextLoader,
                onTranscribeNow: { [weak transcription] in
                    Task { @MainActor in
                        await transcription?.forceTranscribeAll()
                    }
                },
                onRecordingModeChanged: { [weak self] newMode in
                    self?.applyRecordingMode(newMode)
                },
                onQuit: { [weak self] in
                    self?.manualQuit()
                }
            )
            statusBarController = controller

            registerLoginItemIfPossible()

            // Phase 1 identity flip: build the recording policy from user's
            // stored preference and route launch through it. The policy
            // decides whether to auto-start (only Rogue does).
            let currentMode = UserDefaults.standard.recordingMode
            model.recordingMode = currentMode
            let policy = RecordingPolicyFactory.make(
                mode: currentMode,
                dependencies: RecordingPolicyDependencies(
                    recordingService: service,
                    appModel: model,
                    requestMicrophoneThenStart: { [weak self] in
                        self?.requestMicrophoneThenStart()
                    }
                )
            )
            self.recordingPolicy = policy

            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboarding()
            } else {
                policy.appLaunched()
                // Phase 1: open the main window on launch so users immediately
                // see the new briefing dashboard identity. (Previously the app
                // lived as accessory-only and you had to click the status bar
                // icon to see anything.)
                controller.openMainWindow()
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
        meetingTriggerWatcher?.stop()
        digestScheduler?.stop()
        eventStore?.markCleanShutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowManualTermination ? .terminateNow : .terminateCancel
    }

    /// Swap the active recording policy at runtime. Called by StatusBarController
    /// when the user picks a new mode from the context menu.
    private func applyRecordingMode(_ newMode: RecordingMode) {
        // Stop any in-flight recording from the old policy.
        recordingPolicy?.userRequestedStop()

        // Persist and publish the new mode.
        UserDefaults.standard.recordingMode = newMode
        model.recordingMode = newMode

        // Build a fresh policy and let it decide whether to start recording.
        guard let service = recordingService else { return }
        let policy = RecordingPolicyFactory.make(
            mode: newMode,
            dependencies: RecordingPolicyDependencies(
                recordingService: service,
                appModel: model,
                requestMicrophoneThenStart: { [weak self] in
                    self?.requestMicrophoneThenStart()
                }
            )
        )
        self.recordingPolicy = policy
        policy.appLaunched()
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
        meetingTriggerWatcher?.stop()
        digestScheduler?.stop()
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
            // After onboarding completes, hand off to the active policy.
            // Gentle/Manual do nothing; Rogue starts recording.
            self?.recordingPolicy?.appLaunched()
            self?.statusBarController?.openMainWindow()
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
