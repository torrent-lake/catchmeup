import Foundation

struct DayDurations: Sendable {
    let recordedSeconds: TimeInterval
    let gapSeconds: TimeInterval
}

enum DayBinMapper {
    private static let binDuration: TimeInterval = 15 * 60
    private static let totalBins = 96

    static func emptyBins(for day: Date, calendar: Calendar = .current) -> [DayBin] {
        let dayStart = calendar.startOfDay(for: day)
        return (0..<totalBins).map { index in
            let startAt = dayStart.addingTimeInterval(TimeInterval(index) * binDuration)
            let endAt = startAt.addingTimeInterval(binDuration)
            return DayBin(index0to95: index, startAt: startAt, endAt: endAt, status: .none)
        }
    }

    static func map(
        day: Date,
        segments: [RecordingSegment],
        gaps: [GapEvent],
        loudness: [LoudnessEvent] = [],
        calendar: Calendar = .current
    ) -> [DayBin] {
        var bins = emptyBins(for: day, calendar: calendar)
        mark(gaps: gaps, into: &bins, day: day, calendar: calendar)
        mark(segments: segments, into: &bins, day: day, calendar: calendar)
        applyLoudness(loudness, into: &bins, day: day, calendar: calendar)
        return bins
    }

    static func durations(
        day: Date,
        segments: [RecordingSegment],
        gaps: [GapEvent],
        calendar: Calendar = .current
    ) -> DayDurations {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayDurations(recordedSeconds: 0, gapSeconds: 0)
        }

        let recorded = segments.reduce(into: 0.0) { partialResult, segment in
            partialResult += overlapDuration(
                lhsStart: dayStart,
                lhsEnd: dayEnd,
                rhsStart: segment.startAt,
                rhsEnd: segment.endAt
            )
        }

        let gap = gaps.reduce(into: 0.0) { partialResult, event in
            partialResult += overlapDuration(
                lhsStart: dayStart,
                lhsEnd: dayEnd,
                rhsStart: event.startAt,
                rhsEnd: event.endAt
            )
        }

        return DayDurations(recordedSeconds: recorded, gapSeconds: gap)
    }

    private static func mark(
        segments: [RecordingSegment],
        into bins: inout [DayBin],
        day: Date,
        calendar: Calendar
    ) {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        for segment in segments {
            guard overlaps(start: segment.startAt, end: segment.endAt, withStart: dayStart, withEnd: dayEnd) else {
                continue
            }
            let indexes = overlappingIndexes(
                eventStart: segment.startAt,
                eventEnd: segment.endAt,
                dayStart: dayStart
            )
            for index in indexes where bins.indices.contains(index) {
                bins[index].status = .recorded
                if bins[index].recordingIntensity == 0 {
                    bins[index].recordingIntensity = 0.18
                }
            }
        }
    }

    private static func mark(
        gaps: [GapEvent],
        into bins: inout [DayBin],
        day: Date,
        calendar: Calendar
    ) {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        for gap in gaps {
            guard overlaps(start: gap.startAt, end: gap.endAt, withStart: dayStart, withEnd: dayEnd) else {
                continue
            }
            let indexes = overlappingIndexes(
                eventStart: gap.startAt,
                eventEnd: gap.endAt,
                dayStart: dayStart
            )
            for index in indexes where bins.indices.contains(index) && bins[index].status == .none {
                bins[index].status = .gap
            }
        }
    }

    private static func applyLoudness(
        _ loudnessEvents: [LoudnessEvent],
        into bins: inout [DayBin],
        day: Date,
        calendar: Calendar
    ) {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        var aggregate: [Int: (sum: Double, count: Int)] = [:]
        for event in loudnessEvents {
            guard event.sampledAt >= dayStart, event.sampledAt < dayEnd else { continue }
            let offset = event.sampledAt.timeIntervalSince(dayStart)
            let index = min(totalBins - 1, max(0, Int(offset / binDuration)))
            var bucket = aggregate[index] ?? (0, 0)
            bucket.sum += max(0, min(1, event.normalizedLevel))
            bucket.count += 1
            aggregate[index] = bucket
        }

        for index in bins.indices where bins[index].status == .recorded {
            guard let bucket = aggregate[index], bucket.count > 0 else { continue }
            let average = bucket.sum / Double(bucket.count)
            bins[index].recordingIntensity = max(0.08, min(1, average))
        }
    }

    private static func overlappingIndexes(eventStart: Date, eventEnd: Date, dayStart: Date) -> ClosedRange<Int> {
        let clampedEnd = max(eventStart, eventEnd.addingTimeInterval(-1))
        let startOffset = max(0, eventStart.timeIntervalSince(dayStart))
        let endOffset = max(0, clampedEnd.timeIntervalSince(dayStart))
        let startIndex = min(totalBins - 1, Int(startOffset / binDuration))
        let endIndex = min(totalBins - 1, Int(endOffset / binDuration))
        return startIndex...max(startIndex, endIndex)
    }

    private static func overlaps(start: Date, end: Date, withStart: Date, withEnd: Date) -> Bool {
        start < withEnd && end > withStart
    }

    private static func overlapDuration(lhsStart: Date, lhsEnd: Date, rhsStart: Date, rhsEnd: Date) -> TimeInterval {
        let start = max(lhsStart, rhsStart)
        let end = min(lhsEnd, rhsEnd)
        return max(0, end.timeIntervalSince(start))
    }
}
