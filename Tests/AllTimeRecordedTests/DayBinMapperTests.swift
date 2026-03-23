import Foundation
import Testing
@testable import AllTimeRecorded

struct DayBinMapperTests {
    @Test
    func segmentMapsToExpectedBins() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = makeDate("2026-02-18T00:00:00Z")
        let segment = RecordingSegment(
            id: UUID(),
            startAt: makeDate("2026-02-18T09:00:00Z"),
            endAt: makeDate("2026-02-18T10:00:00Z"),
            fileURL: URL(fileURLWithPath: "/tmp/1.m4a"),
            bytes: 1000,
            sourceDeviceID: 1
        )

        let bins = DayBinMapper.map(day: day, segments: [segment], gaps: [], calendar: calendar)
        let recordedIndexes = Set(bins.filter { $0.status == .recorded }.map(\.index0to95))
        #expect(recordedIndexes == Set([36, 37, 38, 39]))
    }

    @Test
    func gapMarksOnlyEmptyBins() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = makeDate("2026-02-18T00:00:00Z")
        let segment = RecordingSegment(
            id: UUID(),
            startAt: makeDate("2026-02-18T10:00:00Z"),
            endAt: makeDate("2026-02-18T11:00:00Z"),
            fileURL: URL(fileURLWithPath: "/tmp/2.m4a"),
            bytes: 1000,
            sourceDeviceID: 1
        )
        let gap = GapEvent(
            id: UUID(),
            startAt: makeDate("2026-02-18T10:30:00Z"),
            endAt: makeDate("2026-02-18T11:00:00Z"),
            reason: .forcedSleep
        )

        let bins = DayBinMapper.map(day: day, segments: [segment], gaps: [gap], calendar: calendar)
        #expect(bins[42].status == .recorded)
        #expect(bins[43].status == .recorded)
    }

    @Test
    func durationsClampToDayBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = makeDate("2026-02-18T00:00:00Z")
        let segment = RecordingSegment(
            id: UUID(),
            startAt: makeDate("2026-02-17T23:30:00Z"),
            endAt: makeDate("2026-02-18T00:30:00Z"),
            fileURL: URL(fileURLWithPath: "/tmp/3.m4a"),
            bytes: 1000,
            sourceDeviceID: 1
        )

        let durations = DayBinMapper.durations(day: day, segments: [segment], gaps: [], calendar: calendar)
        #expect(durations.recordedSeconds == 1800)
        #expect(durations.gapSeconds == 0)
    }

    @Test
    func loudnessChangesBinIntensity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = makeDate("2026-02-18T00:00:00Z")
        let segment = RecordingSegment(
            id: UUID(),
            startAt: makeDate("2026-02-18T12:00:00Z"),
            endAt: makeDate("2026-02-18T12:15:00Z"),
            fileURL: URL(fileURLWithPath: "/tmp/4.m4a"),
            bytes: 1000,
            sourceDeviceID: 1
        )
        let samples = [
            LoudnessEvent(id: UUID(), sampledAt: makeDate("2026-02-18T12:05:00Z"), normalizedLevel: 0.95),
            LoudnessEvent(id: UUID(), sampledAt: makeDate("2026-02-18T12:10:00Z"), normalizedLevel: 0.85),
        ]

        let bins = DayBinMapper.map(day: day, segments: [segment], gaps: [], loudness: samples, calendar: calendar)
        #expect(bins[48].status == .recorded)
        #expect(bins[48].recordingIntensity > 0.8)
    }

    private func makeDate(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let value = formatter.date(from: iso8601) else {
            Issue.record("Invalid test date")
            return Date(timeIntervalSince1970: 0)
        }
        return value
    }
}
