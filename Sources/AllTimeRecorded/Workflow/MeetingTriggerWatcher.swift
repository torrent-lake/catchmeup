import Combine
import Foundation

/// Watches the calendar for upcoming meetings and triggers notifications.
/// Simplified design: just fires a status bar notification when a meeting
/// is approaching, with the option to generate a pre-meeting brief.
@MainActor
final class MeetingTriggerWatcher: ObservableObject {
    @Published private(set) var upcomingMeeting: UpcomingMeeting?

    private let calendarService: CalendarOverlayService
    private let briefingService: BriefingService
    private var nudgedEventIDs = Set<String>()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    struct UpcomingMeeting: Sendable {
        let event: CalendarOverlayEvent
        let minutesAway: Int
        let briefReady: Bool
    }

    init(
        calendarService: CalendarOverlayService,
        briefingService: BriefingService
    ) {
        self.calendarService = calendarService
        self.briefingService = briefingService
    }

    func start() {
        // Check every 60 seconds for upcoming meetings
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkUpcoming()
            }
        }
        // Also check immediately
        checkUpcoming()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkUpcoming() {
        let now = Date()
        let lookahead: TimeInterval = 30 * 60  // 30 minutes

        let upcoming = calendarService.currentEvents.filter { event in
            let timeUntil = event.startAt.timeIntervalSince(now)
            return timeUntil > 0 && timeUntil <= lookahead
        }.sorted { $0.startAt < $1.startAt }

        guard let next = upcoming.first else {
            upcomingMeeting = nil
            return
        }

        let minutes = Int(next.startAt.timeIntervalSince(now) / 60)

        // Only nudge once per event at the 5-minute mark
        if minutes <= 5 && !nudgedEventIDs.contains(next.uid) {
            nudgedEventIDs.insert(next.uid)
            sendNotification(for: next, minutesAway: minutes)
        }

        upcomingMeeting = UpcomingMeeting(
            event: next,
            minutesAway: minutes,
            briefReady: false
        )
    }

    private func sendNotification(for event: CalendarOverlayEvent, minutesAway: Int) {
        let center = NSUserNotificationCenter.default
        let notification = NSUserNotification()
        notification.title = "Meeting in \(minutesAway) min"
        notification.subtitle = event.title
        notification.informativeText = "Tap to get a quick briefing"
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = true
        notification.actionButtonTitle = "Brief Me"
        center.deliver(notification)
    }
}
