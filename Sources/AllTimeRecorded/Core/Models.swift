import Foundation

enum RecorderState: String, Codable, Sendable {
    case recording
    case pausedLowDisk
    case blockedNoPermission
    case recovering
}

struct RecordingSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let startAt: Date
    let endAt: Date
    let fileURL: URL
    let bytes: Int64
    let sourceDeviceID: UInt32
}

enum GapReason: String, Codable, Sendable {
    case forcedSleep
    case appRelaunchRecovery
    case lowDiskPause
    case inputDeviceLost
}

struct GapEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let startAt: Date
    let endAt: Date
    let reason: GapReason
}

struct LoudnessEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let sampledAt: Date
    let normalizedLevel: Double
}

enum DayBinStatus: String, Codable, Sendable {
    case none
    case recorded
    case gap
}

struct DayBin: Identifiable, Codable, Sendable {
    let index0to95: Int
    let startAt: Date
    let endAt: Date
    var status: DayBinStatus
    var recordingIntensity: Double = 0

    var id: Int { index0to95 }
}

enum RecordingStopReason: String, Sendable {
    case userQuit
    case forcedSleep
    case lowDiskPause
    case inputDeviceLost
    case internalRecovery
}

struct RecordingSnapshot: Sendable {
    let state: RecorderState
    let bins: [DayBin]
    let recordedSecondsToday: TimeInterval
    let gapSecondsToday: TimeInterval
    let freeSpaceBytes: Int64
    let updatedAt: Date

    static func empty(now: Date = Date()) -> RecordingSnapshot {
        RecordingSnapshot(
            state: .recovering,
            bins: DayBinMapper.emptyBins(for: now),
            recordedSecondsToday: 0,
            gapSecondsToday: 0,
            freeSpaceBytes: 0,
            updatedAt: now
        )
    }
}
