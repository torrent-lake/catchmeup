import EventKit
import Foundation

/// Data source that queries system Calendar events via EventKit.
/// Does NOT use LEANN — events are structured data already, so we
/// query EventKit directly and format them as SourceChunks.
///
/// Queries events from the past 30 days and next 14 days, then
/// keyword-filters on the question text. This gives the RAG pipeline
/// calendar context without needing a separate index.
final class CalendarDataSource: DataSource, @unchecked Sendable {
    let id = "calendar"
    let displayName = "Calendar"
    let requiresConsent = false  // user's own calendar

    private let eventStore = EKEventStore()

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        let hasAccess = await requestAccess()
        guard hasAccess else { return [] }

        let now = Date()
        let lookBack: TimeInterval = 30 * 86_400   // 30 days
        let lookAhead: TimeInterval = 14 * 86_400   // 14 days
        let start = now.addingTimeInterval(-lookBack)
        let end = now.addingTimeInterval(lookAhead)

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil  // all calendars
        )
        let events = eventStore.events(matching: predicate)

        // Keyword filter: extract words from the question and match against
        // event title, location, notes.
        let keywords = Self.extractKeywords(from: question)

        let matched: [(event: EKEvent, relevance: Double)] = events.compactMap { event in
            let searchable = [
                event.title ?? "",
                event.location ?? "",
                event.notes ?? "",
            ].joined(separator: " ").lowercased()

            let hits = keywords.filter { searchable.contains($0) }
            guard !hits.isEmpty else { return nil }
            let relevance = Double(hits.count) / Double(max(keywords.count, 1))
            return (event, relevance)
        }

        let sorted = matched
            .sorted { $0.relevance > $1.relevance }
            .prefix(topK)

        return sorted.map { item in
            let event = item.event
            let body = Self.formatEventBody(event)
            return SourceChunk(
                id: "calendar#\(event.calendarItemIdentifier)",
                sourceID: "calendar",
                title: event.title ?? "(Untitled Event)",
                body: body,
                timestamp: event.startDate,
                originURI: "x-apple-calevent://\(event.calendarItemIdentifier)",
                score: item.relevance
            )
        }
    }

    private func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    static func extractKeywords(from question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "about", "what", "when",
            "where", "who", "how", "which", "that", "this", "with", "from", "for",
            "and", "but", "or", "not", "no", "in", "on", "at", "to", "of", "by",
            "my", "me", "i", "you", "your", "it", "its", "we", "our", "they",
            "their", "any", "all", "some", "most", "more", "than", "if", "so",
            "up", "out", "just", "also", "very", "too", "only",
            "明天", "今天", "昨天", "什么", "哪个", "哪些", "有没有", "是不是",
            "吗", "呢", "的", "了", "在", "和", "与", "或", "我", "你", "他", "她",
        ]
        let words = question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        return Array(Set(words))
    }

    private static func formatEventBody(_ event: EKEvent) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        var lines: [String] = []
        lines.append("Event: \(event.title ?? "(Untitled)")")
        lines.append("Time: \(df.string(from: event.startDate)) – \(df.string(from: event.endDate))")
        if let loc = event.location, !loc.isEmpty {
            lines.append("Location: \(loc)")
        }
        if let cal = event.calendar {
            lines.append("Calendar: \(cal.title)")
        }
        if event.hasAttendees, let attendees = event.attendees {
            let names = attendees.compactMap { $0.name ?? $0.url.absoluteString }.prefix(10)
            if !names.isEmpty {
                lines.append("Attendees: \(names.joined(separator: ", "))")
            }
        }
        if let notes = event.notes, !notes.isEmpty {
            lines.append("Notes: \(String(notes.prefix(500)))")
        }
        return lines.joined(separator: "\n")
    }
}
