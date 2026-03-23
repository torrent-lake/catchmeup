import Foundation

struct CalendarOverlayEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let uid: String
    let title: String
    let startAt: Date
    let endAt: Date
    let sourceID: String
    let sourceName: String
    let colorHex: String
    let location: String?
    let notePreview: String?
}

struct CalendarArcSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let eventID: UUID
    let eventTitle: String
    let sourceName: String
    let startRatio: Double
    let endRatio: Double
    let row: Int
    let colorHex: String
    let alpha: Double
    let startAt: Date
    let endAt: Date
}

struct CalendarSourceItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case localICS
        case systemCalendar
    }

    let id: String
    let kind: Kind
    let displayName: String
    var enabled: Bool
    var colorHex: String
}

struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startAt: Date
    let endAt: Date
    let text: String
    let sourceFile: String
    let sourceOffsetStart: TimeInterval
    let sourceOffsetEnd: TimeInterval
}

struct TranscriptDay: Codable, Sendable {
    let day: String
    let modelID: String
    let generatedAt: Date
    let languageMode: String
    let segments: [TranscriptSegment]
}

enum ModelDownloadState: Codable, Hashable, Sendable {
    case idle
    case downloading(progress: Double)
    case verifying
    case ready(path: String)
    case failed(message: String)
}
