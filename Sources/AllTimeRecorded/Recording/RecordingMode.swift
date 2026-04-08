import Foundation

/// Recording behavior mode. Controls how and when CatchMeUp captures audio.
///
/// See `docs/PLAN.md` §2 D4 and §7 for the full rationale.
enum RecordingMode: String, CaseIterable, Codable, Sendable {
    /// Default. Calendar-driven nudges. No auto-record on launch.
    /// Status bar icon turns amber at T-5 before a meeting; user taps to enable.
    case gentle

    /// User-driven only. No auto-triggers of any kind. User starts/stops explicitly.
    case manual

    /// Legacy open-lid behavior: recording auto-starts at launch and runs continuously.
    /// Opt-in for users who want the dashcam-style capture from AllTimeRecorded.
    case rogue

    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .manual: return "Manual"
        case .rogue:  return "Rogue"
        }
    }

    var shortDescription: String {
        switch self {
        case .gentle: return "Calendar-driven nudges. Opt-in per meeting."
        case .manual: return "You start and stop recording. Nothing automatic."
        case .rogue:  return "Open-lid to record. Legacy behavior from AllTimeRecorded."
        }
    }
}

extension UserDefaults {
    private static let recordingModeKey = "CatchMeUp.recordingMode"

    /// Current recording mode. Defaults to `.gentle` on first launch.
    var recordingMode: RecordingMode {
        get {
            guard let raw = string(forKey: Self.recordingModeKey),
                  let mode = RecordingMode(rawValue: raw)
            else { return .gentle }
            return mode
        }
        set {
            set(newValue.rawValue, forKey: Self.recordingModeKey)
        }
    }
}
