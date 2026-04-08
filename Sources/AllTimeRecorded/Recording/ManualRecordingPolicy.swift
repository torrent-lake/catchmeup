import Foundation

/// Strict user-driven recording. Nothing automatic. No calendar nudges,
/// no open-lid triggers, no scheduled digest interactions with recording.
/// The user starts and stops recording explicitly.
///
/// This is for users who want CatchMeUp's retrieval layer (mail / WeChat /
/// files indexing, on-demand briefings) but do NOT want any new audio
/// captured unless they explicitly ask for it.
@MainActor
final class ManualRecordingPolicy: RecordingPolicy {
    let mode: RecordingMode = .manual
    private let dependencies: RecordingPolicyDependencies

    init(dependencies: RecordingPolicyDependencies) {
        self.dependencies = dependencies
    }

    func appLaunched() {
        // No-op. Recording never starts automatically in manual mode.
    }

    func meetingStartingSoon(_ event: CalendarOverlayEvent, minutesAhead: Int) {
        // No-op. Manual mode ignores calendar triggers for recording.
        // Pre-meeting briefs still generate via BriefingService (non-recording path).
    }

    func meetingEnded(_ event: CalendarOverlayEvent) {
        // No-op.
    }

    func userRequestedStart() {
        dependencies.requestMicrophoneThenStart?()
    }

    func userRequestedStop() {
        dependencies.recordingService?.stop(reason: .userQuit)
    }
}
