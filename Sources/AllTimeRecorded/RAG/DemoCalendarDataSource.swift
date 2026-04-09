import Foundation

/// Deterministic "demo mode" replacement for `CalendarDataSource`.
///
/// Returns a fixed set of 4 events for 2026-01-28 (Wednesday) regardless of
/// the query text. This is deliberately a dumb retriever — determinism matters
/// for a 10-minute pitch demo where the narrator wants to show the same output
/// every take. The `CrossRefEngine` reranks these alongside real mail/wechat
/// chunks so the cross-source stitching still looks real.
///
/// Keeps the same `id = "calendar"` as the real source so citation ordering
/// and guardrail rules don't have to special-case the demo.
struct DemoCalendarDataSource: DataSource {
    let id = "calendar"
    let displayName = "Calendar (Demo)"
    let requiresConsent = false

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        let events = Self.demoEvents()
        let limited = Array(events.prefix(max(topK, 0)))
        return limited.isEmpty ? events : limited
    }

    // MARK: - Static demo data

    private static func dateFor(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 28
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    private static func demoEvents() -> [SourceChunk] {
        [
            SourceChunk(
                id: "calendar#demo-jan28-1",
                sourceID: "calendar",
                title: "NBA 6170 AI Strategy Lecture",
                body: """
                NBA 6170 AI Strategy Lecture | 09:00–11:00 | Sage Hall B09
                Attendees: Prof. Lutz Finger, NBA 6170 cohort
                Notes: Topic: AI agents, RAG workflows, and guardrails. Bring laptop. \
                Prof Finger will clarify an additional capstone requirement about the \
                confusion-matrix framing for retrieval quality.
                """,
                timestamp: dateFor(hour: 9, minute: 0),
                originURI: "catchmeup://calendar/demo/2026-01-28/event1",
                score: 0.95
            ),
            SourceChunk(
                id: "calendar#demo-jan28-2",
                sourceID: "calendar",
                title: "Drop HADM 4770 with Prof Tarantino",
                body: """
                Drop HADM 4770 with Prof Tarantino | 14:00–14:30 | Zoom
                Attendees: Prof. Tarantino, Yizhi
                Notes: Follow-up on the drop request email from earlier this week. \
                Schedule is overloaded with NBA 6060 and NBA 6170 so dropping HADM 4770 \
                is the right call.
                """,
                timestamp: dateFor(hour: 14, minute: 0),
                originURI: "catchmeup://calendar/demo/2026-01-28/event2",
                score: 0.90
            ),
            SourceChunk(
                id: "calendar#demo-jan28-3",
                sourceID: "calendar",
                title: "Capstone Team 10 sync",
                body: """
                Capstone Team 10 sync | 17:00–18:00 | Coffee at Gimme!
                Attendees: Team 10 (Yizhi, Jin, Priya)
                Notes: Review eval numbers for the AI personal memory pitch. Decide \
                which cross-source example to lead with. Target a real hit-rate screenshot \
                before Friday.
                """,
                timestamp: dateFor(hour: 17, minute: 0),
                originURI: "catchmeup://calendar/demo/2026-01-28/event3",
                score: 0.85
            ),
            SourceChunk(
                id: "calendar#demo-jan28-4",
                sourceID: "calendar",
                title: "CCAL pickup: buy used BA II Plus calculator",
                body: """
                CCAL pickup: buy used BA II Plus calculator | 18:30–19:00 | Collegetown
                Attendees: Seller from CCAL second-hand group
                Notes: Grab the BA II Plus (and maybe the TI-84 bonus) before the AEM 4531 \
                midterm next week. Bring cash.
                """,
                timestamp: dateFor(hour: 18, minute: 30),
                originURI: "catchmeup://calendar/demo/2026-01-28/event4",
                score: 0.80
            ),
        ]
    }
}
