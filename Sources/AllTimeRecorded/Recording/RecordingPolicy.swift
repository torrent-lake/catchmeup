import Foundation

/// Decides when recording happens. CatchMeUp's identity pivot lives here:
/// recording is NOT automatic at launch by default. The policy owns that decision.
///
/// See `docs/PLAN.md` §7 for the three concrete implementations.
@MainActor
protocol RecordingPolicy: AnyObject {
    var mode: RecordingMode { get }

    /// Called once when the app finishes launching. Policies decide whether to
    /// start recording at this moment.
    func appLaunched()

    /// Called by the calendar trigger watcher T-N minutes before a meeting starts.
    /// Only relevant to Gentle (status bar nudge) and Rogue (already recording, no-op).
    /// Phase 2 wires this up — Phase 1 ships empty implementations.
    func meetingStartingSoon(_ event: CalendarOverlayEvent, minutesAhead: Int)

    /// Called when a meeting ends. Policies may stop recording here.
    func meetingEnded(_ event: CalendarOverlayEvent)

    /// User explicitly asked to start recording (via menu item or button).
    /// All policies should honor this.
    func userRequestedStart()

    /// User explicitly asked to stop recording.
    /// All policies should honor this.
    func userRequestedStop()
}

/// Lightweight dependency bundle passed to each policy at construction.
/// We deliberately pass references, not owning them — AppDelegate owns the
/// recording service and the model.
@MainActor
struct RecordingPolicyDependencies {
    weak var recordingService: DefaultRecordingService?
    weak var appModel: AppModel?

    /// Invoked when the policy wants to start recording but has no microphone
    /// permission. The host (AppDelegate) is expected to either request permission
    /// or surface the blocked state to the user.
    var requestMicrophoneThenStart: (@MainActor () -> Void)?
}

/// Factory for building the concrete policy for a given mode.
enum RecordingPolicyFactory {
    @MainActor
    static func make(mode: RecordingMode, dependencies: RecordingPolicyDependencies) -> any RecordingPolicy {
        switch mode {
        case .gentle:
            return GentleRecordingPolicy(dependencies: dependencies)
        case .manual:
            return ManualRecordingPolicy(dependencies: dependencies)
        case .rogue:
            return RogueRecordingPolicy(dependencies: dependencies)
        }
    }
}
