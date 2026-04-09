import Foundation

/// A structured briefing produced by BriefingService — either a pre-meeting
/// brief, a daily digest, or a proactive intelligence response.
struct Briefing: Codable, Sendable, Identifiable {
    let id: UUID
    let kind: Kind
    let generatedAt: Date
    let title: String
    let highlights: [Highlight]
    let actionItems: [ActionItem]
    let youMayHaveMissed: [Highlight]?
    let lookingAhead: [Highlight]?
    let rawAnswer: String
    let citedChunks: [SourceChunk]

    enum Kind: String, Codable, Sendable {
        case preMeeting
        case dailyDigest
        case proactive
    }
}

struct Highlight: Codable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let sourceIDs: [Int]   // 1-based citation IDs matching chunk order
}

struct ActionItem: Codable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let sourceIDs: [Int]
    let dueHint: String?   // e.g., "tomorrow", "by Friday"
}
