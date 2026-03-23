import Foundation
import Testing
@testable import AllTimeRecorded

struct ICSBasicParserTests {
    @Test
    func parsesBasicVEVENT() {
        let ics = """
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:test-1
SUMMARY:Planning
DTSTART:20260219T090000Z
DTEND:20260219T100000Z
LOCATION:Room A
DESCRIPTION:Weekly sync
END:VEVENT
END:VCALENDAR
"""
        let events = ICSBasicParser.parseEvents(
            from: ics,
            sourceID: "ics::test",
            sourceName: "test",
            colorHex: "#6AF2FF"
        )
        #expect(events.count == 1)
        let event = events[0]
        #expect(event.uid == "test-1")
        #expect(event.title == "Planning")
        #expect(event.location == "Room A")
        #expect(event.notePreview == "Weekly sync")
        #expect(event.endAt > event.startAt)
    }

    @Test
    func unfoldsFoldedLines() {
        let ics = """
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:test-2
SUMMARY:Long
 description title
DTSTART:20260219T120000Z
DTEND:20260219T130000Z
END:VEVENT
END:VCALENDAR
"""
        let events = ICSBasicParser.parseEvents(
            from: ics,
            sourceID: "ics::test",
            sourceName: "test",
            colorHex: "#6AF2FF"
        )
        #expect(events.count == 1)
        #expect(events[0].title.contains("description"))
    }
}
