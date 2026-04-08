import Foundation
import SwiftUI

@MainActor
final class RecallPanelViewModel: ObservableObject {
    @Published var queryText = ""
    @Published var state: QueryState = .idle
    @Published var hoveredResultID: UUID?
    @Published var highlightedTimeRanges: [DateInterval] = []

    private let queryService: any QueryService
    private var searchTask: Task<Void, Never>?

    init(queryService: any QueryService) {
        self.queryService = queryService
    }

    func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        state = .searching
        highlightedTimeRanges = []

        searchTask = Task {
            do {
                let results = try await queryService.search(query: trimmed, dayRange: nil)
                guard !Task.isCancelled else { return }

                if results.isEmpty {
                    state = .noResults
                    highlightedTimeRanges = []
                } else {
                    let groups = groupByDay(results)
                    state = .results(groups, totalCount: results.count)
                    highlightedTimeRanges = results.map(\.timeRange)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(error.localizedDescription)
                highlightedTimeRanges = []
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        queryText = ""
        state = .idle
        hoveredResultID = nil
        highlightedTimeRanges = []
    }

    func hoverResult(_ result: QueryResult?) {
        hoveredResultID = result?.id
        if let result {
            highlightedTimeRanges = [result.timeRange]
        } else if case .results(let groups, _) = state {
            highlightedTimeRanges = groups.flatMap { $0.results.map(\.timeRange) }
        }
    }

    var dayCountLabel: String {
        guard case .results(let groups, _) = state else { return "" }
        let days = groups.count
        return days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - Private

    private func groupByDay(_ results: [QueryResult]) -> [QueryResultGroup] {
        var dict: [String: [QueryResult]] = [:]
        for result in results {
            dict[result.day, default: []].append(result)
        }
        return dict.sorted { $0.key > $1.key }.map {
            QueryResultGroup(day: $0.key, results: $0.value)
        }
    }
}
