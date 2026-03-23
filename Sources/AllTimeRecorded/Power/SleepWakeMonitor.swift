import AppKit
import Foundation

final class SleepWakeMonitor {
    var onWillSleep: (@Sendable () -> Void)?
    var onDidWake: (@Sendable () -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let willSleepHandler = onWillSleep
        let didWakeHandler = onDidWake
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                willSleepHandler?()
            }
        )
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                didWakeHandler?()
            }
        )
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    deinit {
        stop()
    }
}
