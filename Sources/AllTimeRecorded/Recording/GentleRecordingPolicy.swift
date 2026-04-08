import Foundation

/// The default recording policy for CatchMeUp.
///
/// Gentle mode is *deliberately passive* at launch. It does NOT call
/// `recordingService.start()` in `appLaunched()`. Instead, the app opens
/// to the briefing dashboard with recording off, and recording only kicks in
/// when either:
///   1. The `MeetingTriggerWatcher` detects an upcoming calendar event and
///      the user explicitly taps the amber status bar nudge (Phase 2), OR
///   2. The user explicitly calls `userRequestedStart()` from a UI control.
///
/// This is the single biggest behavioral shift from AllTimeRecorded, which
/// auto-started on launch. See `docs/PLAN.md` §1 for why.
@MainActor
final class GentleRecordingPolicy: RecordingPolicy {
    let mode: RecordingMode = .gentle
    private let dependencies: RecordingPolicyDependencies

    init(dependencies: RecordingPolicyDependencies) {
        self.dependencies = dependencies
    }

    func appLaunched() {
        // Intentionally does nothing. Recording stays off.
        // The user opens the app and sees the briefing dashboard, not a recording state.
    }

    func meetingStartingSoon(_ event: CalendarOverlayEvent, minutesAhead: Int) {
        // Phase 2: show amber status bar nudge + popover with [Brief] [Record] [Dismiss].
        // Phase 1 stub: log and do nothing.
    }

    func meetingEnded(_ event: CalendarOverlayEvent) {
        // If the user enabled recording for this meeting, stop it now.
        // Phase 1: if recording was started via userRequestedStart, we don't auto-stop
        // — the user decides when to stop. Phase 2 refines this with per-meeting state.
    }

    func userRequestedStart() {
        dependencies.requestMicrophoneThenStart?()
    }

    func userRequestedStop() {
        dependencies.recordingService?.stop(reason: .userQuit)
    }
}
