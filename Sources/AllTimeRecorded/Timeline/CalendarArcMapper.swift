import Foundation

enum CalendarArcMapper {
    private struct Pending {
        let event: CalendarOverlayEvent
        let startAt: Date
        let endAt: Date
        let startRatio: Double
        let endRatio: Double
    }

    static func map(
        day: Date,
        events: [CalendarOverlayEvent],
        calendar: Calendar = .current
    ) -> [CalendarArcSegment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let daySeconds = dayEnd.timeIntervalSince(dayStart)
        guard daySeconds > 0 else { return [] }

        var pending: [Pending] = []
        pending.reserveCapacity(events.count)

        for event in events {
            let clippedStart = max(dayStart, event.startAt)
            let clippedEnd = min(dayEnd, event.endAt)
            guard clippedEnd > clippedStart else { continue }

            // Ignore all-day style entries that visually flood the whole grid.
            let startsAtDayBoundary = abs(clippedStart.timeIntervalSince(dayStart)) <= 60
            let endsAtDayBoundary = abs(clippedEnd.timeIntervalSince(dayEnd)) <= 60
            if startsAtDayBoundary && endsAtDayBoundary {
                continue
            }

            let startRatio = clippedStart.timeIntervalSince(dayStart) / daySeconds
            let endRatio = clippedEnd.timeIntervalSince(dayStart) / daySeconds
            pending.append(
                Pending(
                    event: event,
                    startAt: clippedStart,
                    endAt: clippedEnd,
                    startRatio: max(0, min(1, startRatio)),
                    endRatio: max(0, min(1, endRatio))
                )
            )
        }

        pending.sort {
            if $0.startRatio == $1.startRatio {
                return $0.endRatio < $1.endRatio
            }
            return $0.startRatio < $1.startRatio
        }

        var rowEndRatios: [Double] = []
        var arcs: [CalendarArcSegment] = []
        arcs.reserveCapacity(pending.count)

        for item in pending {
            let row = assignRow(for: item, rowEndRatios: &rowEndRatios)
            arcs.append(
                CalendarArcSegment(
                    id: UUID(),
                    eventID: item.event.id,
                    eventTitle: item.event.title,
                    sourceName: item.event.sourceName,
                    startRatio: item.startRatio,
                    endRatio: item.endRatio,
                    row: row,
                    colorHex: item.event.colorHex,
                    alpha: 0.36,
                    startAt: item.startAt,
                    endAt: item.endAt
                )
            )
        }
        return arcs
    }

    private static func assignRow(
        for item: Pending,
        rowEndRatios: inout [Double]
    ) -> Int {
        for index in rowEndRatios.indices where item.startRatio >= rowEndRatios[index] {
            rowEndRatios[index] = item.endRatio
            return index
        }
        rowEndRatios.append(item.endRatio)
        return rowEndRatios.count - 1
    }
}
