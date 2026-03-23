import Foundation
import Testing
@testable import AllTimeRecorded

struct TimelineNowMarkerTests {
    @Test
    func mapsDateToExpectedBinIndex() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = makeDate("2026-02-19T12:34:56Z")

        let index = TimelineGeometry.currentBinIndex(at: date, calendar: calendar)
        #expect(index == 50)
    }

    @Test
    func pointsToExpectedBinBottomCenter() {
        let point = TimelineGeometry.binBottomCenter(
            index: 50,
            columns: 24,
            cellWidth: 3,
            cellHeight: 18,
            spacing: 1
        )

        #expect(abs(point.x - 9.5) < 0.001)
        #expect(abs(point.y - 56.0) < 0.001)
    }

    @Test
    func pointsToExpectedBinCenter() {
        let point = TimelineGeometry.binCenter(
            index: 50,
            columns: 24,
            cellWidth: 3,
            cellHeight: 18,
            spacing: 1
        )

        #expect(abs(point.x - 9.5) < 0.001)
        #expect(abs(point.y - 47.0) < 0.001)
    }

    @Test
    func pointerEndsAtTargetPoint() {
        let target = TimelineGeometry.binCenter(
            index: 72,
            columns: 24,
            cellWidth: 3,
            cellHeight: 18,
            spacing: 1
        )
        let points = TimelineGeometry.nowPointerPoints(target: target, canvasWidth: 128, markerHeight: 75)
        #expect(abs(points.end.x - target.x) < 0.001)
        #expect(abs(points.end.y - target.y) < 0.001)
    }

    @Test
    func pointerHasHorizontalLeadSegmentOnStartSide() {
        let target = CGPoint(x: 30, y: 45)
        let points = TimelineGeometry.nowPointerPoints(target: target, canvasWidth: 128, markerHeight: 75)
        #expect(abs(points.start.y - points.midA.y) < 0.001)
        #expect(points.start.x < points.midA.x)
    }

    @Test
    func pointerStartsFromSameSideAsTarget() {
        let leftTarget = CGPoint(x: 32, y: 44)
        let rightTarget = CGPoint(x: 112, y: 44)

        let left = TimelineGeometry.nowPointerPoints(target: leftTarget, canvasWidth: 144, markerHeight: 75)
        let right = TimelineGeometry.nowPointerPoints(target: rightTarget, canvasWidth: 144, markerHeight: 75)

        #expect(left.startFromLeft == true)
        #expect(left.start.x <= 24)
        #expect(right.startFromLeft == false)
        #expect(right.start.x >= 120)
    }

    private func makeDate(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso8601) ?? Date(timeIntervalSince1970: 0)
    }
}
