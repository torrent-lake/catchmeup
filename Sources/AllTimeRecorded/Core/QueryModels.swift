import Foundation

struct QueryResult: Identifiable, Sendable {
    let id: UUID
    let text: String
    let day: String
    let timeLabel: String
    let timeRange: DateInterval
    let sourceFile: String
    let relevanceHint: Double
}

struct QueryResultGroup: Identifiable, Sendable {
    var id: String { day }
    let day: String
    let results: [QueryResult]
}

enum QueryState: Sendable {
    case idle
    case searching
    case results([QueryResultGroup], totalCount: Int)
    case noResults
    case error(String)
}
