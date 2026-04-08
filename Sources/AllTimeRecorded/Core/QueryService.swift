import Foundation

protocol QueryService: Sendable {
    func search(query: String, dayRange: ClosedRange<String>?) async throws -> [QueryResult]
}
