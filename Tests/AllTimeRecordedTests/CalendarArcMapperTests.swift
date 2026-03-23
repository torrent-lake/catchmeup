import Foundation
import Testing
@testable import AllTimeRecorded

struct CalendarArcMapperTests {
    @Test
    func clipsEventToDayBounds() {
        let day = makeDate("2026-02-19T00:00:00Z")
        let event = CalendarOverlayEvent(
            id: UUID(),
            uid: "e1",
            title: "Overnight",
            startAt: makeDate("2026-02-18T23:00:00Z"),
            endAt: makeDate("2026-02-19T01:00:00Z"),
            sourceID: "s1",
            sourceName: "A",
            colorHex: "#6AF2FF",
            location: nil,
            notePreview: nil
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let arcs = CalendarArcMapper.map(day: day, events: [event], calendar: calendar)
        #expect(arcs.count == 1)
        #expect(arcs[0].startRatio == 0)
        #expect(arcs[0].endRatio > 0)
    }

    @Test
    func assignsDifferentRowsForOverlaps() {
        let day = makeDate("2026-02-19T00:00:00Z")
        let e1 = makeEvent(uid: "e1", start: "2026-02-19T09:00:00Z", end: "2026-02-19T10:00:00Z")
        let e2 = makeEvent(uid: "e2", start: "2026-02-19T09:30:00Z", end: "2026-02-19T10:30:00Z")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let arcs = CalendarArcMapper.map(day: day, events: [e1, e2], calendar: calendar)
        #expect(arcs.count == 2)
        #expect(Set(arcs.map(\.row)).count == 2)
    }

    private func makeEvent(uid: String, start: String, end: String) -> CalendarOverlayEvent {
        CalendarOverlayEvent(
            id: UUID(),
            uid: uid,
            title: uid,
            startAt: makeDate(start),
            endAt: makeDate(end),
            sourceID: "s1",
            sourceName: "A",
            colorHex: "#6AF2FF",
            location: nil,
            notePreview: nil
        )
    }

    private func makeDate(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso8601) ?? Date(timeIntervalSince1970: 0)
    }
}
