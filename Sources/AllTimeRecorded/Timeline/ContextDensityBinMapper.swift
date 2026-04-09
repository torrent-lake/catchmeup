import Foundation

/// Enriches recording-only `[DayBin]` with per-source context density from
/// email, chat, files, calendar events, and reminders. Each 15-min bin gets
/// a normalised 0-1 density per source. The recording data itself comes from
/// the existing `DayBinMapper`.
enum ContextDensityBinMapper {
    private static let totalBins = 96
    private static let binDuration: TimeInterval = 15 * 60

    // MARK: - Public

    /// Merge context density from multiple sources into existing recording bins.
    ///
    /// - Parameters:
    ///   - recordingBins: Bins already populated by `DayBinMapper.map(…)`.
    ///   - emailChunks: `SourceChunk` items from mail (sourceID == "mail").
    ///   - chatChunks: `SourceChunk` items from chat (sourceID == "wechat" / iMessage).
    ///   - fileChunks: `SourceChunk` items from files (sourceID == "files").
    ///   - reminderChunks: `SourceChunk` items from reminders (sourceID == "reminders").
    ///   - calendarEvents: Calendar overlay events for the day.
    ///   - day: The calendar day being mapped.
    ///   - calendar: Calendar used for day-start computation.
    /// - Returns: Enriched copy of `recordingBins` with density fields populated.
    static func merge(
        recordingBins: [DayBin],
        emailChunks: [SourceChunk] = [],
        chatChunks: [SourceChunk] = [],
        fileChunks: [SourceChunk] = [],
        reminderChunks: [SourceChunk] = [],
        calendarEvents: [CalendarOverlayEvent] = [],
        day: Date,
        calendar: Calendar = .current
    ) -> [DayBin] {
        guard !recordingBins.isEmpty else { return recordingBins }
        var bins = recordingBins
        let dayStart = calendar.startOfDay(for: day)

        applyChunkDensity(chunks: emailChunks, dayStart: dayStart, into: &bins, keyPath: \.emailDensity)
        applyChunkDensity(chunks: chatChunks, dayStart: dayStart, into: &bins, keyPath: \.chatDensity)
        applyChunkDensity(chunks: fileChunks, dayStart: dayStart, into: &bins, keyPath: \.fileDensity)
        applyChunkDensity(chunks: reminderChunks, dayStart: dayStart, into: &bins, keyPath: \.reminderDensity)
        applyCalendarDensity(events: calendarEvents, dayStart: dayStart, into: &bins)

        return bins
    }

    // MARK: - Internal helpers

    /// Count timestamped chunks per bin, then normalise to 0-1 using the
    /// max count across the day (so the busiest bin = 1.0).
    private static func applyChunkDensity(
        chunks: [SourceChunk],
        dayStart: Date,
        into bins: inout [DayBin],
        keyPath: WritableKeyPath<DayBin, Double>
    ) {
        guard !chunks.isEmpty else { return }
        let dayEnd = dayStart.addingTimeInterval(TimeInterval(totalBins) * binDuration)

        var counts = [Int](repeating: 0, count: totalBins)
        for chunk in chunks {
            guard let ts = chunk.timestamp, ts >= dayStart, ts < dayEnd else { continue }
            let offset = ts.timeIntervalSince(dayStart)
            let index = min(totalBins - 1, max(0, Int(offset / binDuration)))
            counts[index] += 1
        }

        let maxCount = counts.max() ?? 0
        guard maxCount > 0 else { return }
        let scale = 1.0 / Double(maxCount)
        for i in bins.indices {
            guard counts[i] > 0 else { continue }
            bins[i][keyPath: keyPath] = min(1.0, Double(counts[i]) * scale)
        }
    }

    /// Calendar events have start/end ranges. Each bin that overlaps an event
    /// gets density proportional to how much of the bin is covered.
    /// All-day events (>= 12 hours) are excluded to avoid flooding the heatmap.
    private static func applyCalendarDensity(
        events: [CalendarOverlayEvent],
        dayStart: Date,
        into bins: inout [DayBin]
    ) {
        guard !events.isEmpty else { return }
        let dayEnd = dayStart.addingTimeInterval(TimeInterval(totalBins) * binDuration)

        // Filter out all-day / very long events (>= 12h). They would paint
        // every bin gold and drown the recording density.
        let timed = events.filter { event in
            event.endAt.timeIntervalSince(event.startAt) < 12 * 3600
        }
        guard !timed.isEmpty else { return }

        var coverage = [Double](repeating: 0, count: totalBins)
        for event in timed {
            let eventStart = max(event.startAt, dayStart)
            let eventEnd = min(event.endAt, dayEnd)
            guard eventStart < eventEnd else { continue }

            let startOffset = eventStart.timeIntervalSince(dayStart)
            let endOffset = eventEnd.timeIntervalSince(dayStart)
            let firstBin = max(0, Int(startOffset / binDuration))
            let lastBin = min(totalBins - 1, Int((endOffset - 1) / binDuration))

            for i in firstBin...max(firstBin, lastBin) {
                let binStart = TimeInterval(i) * binDuration
                let binEnd = binStart + binDuration
                let overlapStart = max(startOffset, binStart)
                let overlapEnd = min(endOffset, binEnd)
                let fraction = max(0, (overlapEnd - overlapStart) / binDuration)
                coverage[i] += fraction
            }
        }

        // Normalize: the busiest bin = 1.0, others proportional.
        let maxCoverage = coverage.max() ?? 0
        guard maxCoverage > 0 else { return }
        for i in bins.indices {
            guard coverage[i] > 0 else { continue }
            bins[i].calendarDensity = min(1.0, coverage[i] / maxCoverage)
        }
    }
}
