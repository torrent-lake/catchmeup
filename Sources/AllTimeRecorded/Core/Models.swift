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
    let systemFileURL: URL?
    let systemBytes: Int64

    init(
        id: UUID,
        startAt: Date,
        endAt: Date,
        fileURL: URL,
        bytes: Int64,
        sourceDeviceID: UInt32,
        systemFileURL: URL? = nil,
        systemBytes: Int64 = 0
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.fileURL = fileURL
        self.bytes = bytes
        self.sourceDeviceID = sourceDeviceID
        self.systemFileURL = systemFileURL
        self.systemBytes = systemBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decode(Date.self, forKey: .endAt)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        sourceDeviceID = try container.decode(UInt32.self, forKey: .sourceDeviceID)
        systemFileURL = try container.decodeIfPresent(URL.self, forKey: .systemFileURL)
        systemBytes = try container.decodeIfPresent(Int64.self, forKey: .systemBytes) ?? 0
    }
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
