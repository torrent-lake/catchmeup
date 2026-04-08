import Foundation

/// Legacy open-lid behavior from AllTimeRecorded. Opt-in only.
///
/// Rogue mode preserves the original AllTimeRecorded experience: recording
/// auto-starts when the app launches, runs continuously, and captures
/// everything the user is near. It's loud, but thorough — the "dashcam for
/// your life" that some users still want.
///
/// This exists so that CatchMeUp does not amputate the original product's
/// value for users who bought into it. The mode toggle in Settings (Phase 3)
/// lets them flip back and forth.
@MainActor
final class RogueRecordingPolicy: RecordingPolicy {
    let mode: RecordingMode = .rogue
    private let dependencies: RecordingPolicyDependencies

    init(dependencies: RecordingPolicyDependencies) {
        self.dependencies = dependencies
    }

    func appLaunched() {
        // Legacy behavior: request mic permission, then start recording.
        dependencies.requestMicrophoneThenStart?()
    }

    func meetingStartingSoon(_ event: CalendarOverlayEvent, minutesAhead: Int) {
        // Already recording in rogue mode. Nothing to do.
    }

    func meetingEnded(_ event: CalendarOverlayEvent) {
        // Keep recording through the day. Rogue is continuous.
    }

    func userRequestedStart() {
        dependencies.requestMicrophoneThenStart?()
    }

    func userRequestedStop() {
        dependencies.recordingService?.stop(reason: .userQuit)
    }
}
