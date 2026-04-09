import Foundation

/// Schedules the daily digest notification at a configurable time (default 7:13 PM).
/// Deliberately off :00/:30 to feel handcrafted and avoid synchronized load.
@MainActor
final class DigestScheduler {
    private let briefingService: BriefingService
    private var timer: Timer?

    /// Hour and minute for the daily digest. Defaults to 19:13 (7:13 PM).
    private let digestHour: Int
    private let digestMinute: Int
    private var lastDigestDate: Date?

    init(
        briefingService: BriefingService,
        digestHour: Int = 19,
        digestMinute: Int = 13
    ) {
        self.briefingService = briefingService
        self.digestHour = digestHour
        self.digestMinute = digestMinute
    }

    func start() {
        // Check every 60 seconds if it's digest time
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkDigestTime()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force-trigger a digest (for debug / demo purposes).
    func triggerNow() {
        Task {
            await fireDigest()
        }
    }

    private func checkDigestTime() {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)

        guard hour == digestHour && minute == digestMinute else { return }

        // Don't fire twice on the same day
        if let last = lastDigestDate,
           cal.isDate(last, inSameDayAs: now) {
            return
        }

        lastDigestDate = now
        Task {
            await fireDigest()
        }
    }

    private func fireDigest() async {
        do {
            let stream = try await briefingService.generateDailyDigest()
            var finalText = ""
            for try await event in stream {
                if case .complete(let text, _) = event {
                    finalText = text
                }
            }

            // Send notification
            let notification = NSUserNotification()
            notification.title = "Your evening catch-up is ready"
            let highlightCount = finalText.components(separatedBy: "**").count / 2
            notification.informativeText = "\(max(highlightCount, 3)) highlights from today"
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
        } catch {
            FileHandle.standardError.write(
                Data("[DigestScheduler] failed: \(error)\n".utf8)
            )
        }
    }
}
