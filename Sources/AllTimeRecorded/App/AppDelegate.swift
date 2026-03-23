import AppKit
import Foundation
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
    private var allowManualTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let paths = AppPaths()
            let store = try EventStore(paths: paths)
            let diskGuard = DefaultDiskGuardService(paths: paths)
            let powerAssertionService = IOKitPowerAssertionService()

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

            statusBarController = StatusBarController(model: model) { [weak self] in
                self?.manualQuit()
            }

            registerLoginItemIfPossible()
            requestMicrophoneThenStart()
        } catch {
            model.setState(.recovering)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingService?.stop(reason: .userQuit)
        sleepWakeMonitor?.stop()
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
        eventStore?.markCleanShutdown()
        NSApp.terminate(nil)
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

