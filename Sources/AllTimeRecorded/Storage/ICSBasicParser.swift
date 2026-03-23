import Foundation

enum ICSBasicParser {
    static func parseEvents(
        from content: String,
        sourceID: String,
        sourceName: String,
        colorHex: String,
        defaultCalendar: Calendar = .current
    ) -> [CalendarOverlayEvent] {
        let unfolded = unfold(content)
        var events: [CalendarOverlayEvent] = []
        var collecting = false
        var props: [String: (params: [String: String], value: String)] = [:]

        for line in unfolded {
            if line == "BEGIN:VEVENT" {
                collecting = true
                props.removeAll(keepingCapacity: true)
                continue
            }
            if line == "END:VEVENT" {
                if let event = makeEvent(
                    from: props,
                    sourceID: sourceID,
                    sourceName: sourceName,
                    colorHex: colorHex,
                    calendar: defaultCalendar
                ) {
                    events.append(event)
                }
                collecting = false
                props.removeAll(keepingCapacity: true)
                continue
            }
            guard collecting else { continue }
            guard let (key, params, value) = splitProperty(line) else { continue }
            if props[key] == nil {
                props[key] = (params, value)
            }
        }
        return events
    }

    static func parseEvents(
        at url: URL,
        sourceID: String,
        sourceName: String,
        colorHex: String,
        defaultCalendar: Calendar = .current
    ) -> [CalendarOverlayEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseEvents(
            from: text,
            sourceID: sourceID,
            sourceName: sourceName,
            colorHex: colorHex,
            defaultCalendar: defaultCalendar
        )
    }

    private static func unfold(_ content: String) -> [String] {
        var output: [String] = []
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard !output.isEmpty else { continue }
                output[output.count - 1].append(line.trimmingCharacters(in: .whitespaces))
            } else {
                output.append(line)
            }
        }
        return output
    }

    private static func splitProperty(_ line: String) -> (String, [String: String], String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let left = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        let pieces = left.split(separator: ";", omittingEmptySubsequences: false)
        guard let first = pieces.first else { return nil }
        let key = String(first).uppercased()
        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let parts = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            params[String(parts[0]).uppercased()] = String(parts[1])
        }
        return (key, params, value)
    }

    private static func makeEvent(
        from props: [String: (params: [String: String], value: String)],
        sourceID: String,
        sourceName: String,
        colorHex: String,
        calendar: Calendar
    ) -> CalendarOverlayEvent? {
        guard let startTuple = props["DTSTART"] else { return nil }
        let endTuple = props["DTEND"]
        guard let startAt = parseICSDate(startTuple.value, params: startTuple.params, calendar: calendar) else { return nil }

        let endAt: Date
        if let endTuple, let parsedEnd = parseICSDate(endTuple.value, params: endTuple.params, calendar: calendar), parsedEnd > startAt {
            endAt = parsedEnd
        } else {
            endAt = startAt.addingTimeInterval(30 * 60)
        }

        let uidValue = props["UID"]?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = props["SUMMARY"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(Untitled Event)"
        let uid = uidValue?.isEmpty == false ? uidValue! : "ics-\(sourceID)-\(startAt.timeIntervalSince1970)-\(title)"
        let location = props["LOCATION"]?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = props["DESCRIPTION"]?.value.trimmingCharacters(in: .whitespacesAndNewlines)

        return CalendarOverlayEvent(
            id: UUID(),
            uid: uid,
            title: title,
            startAt: startAt,
            endAt: endAt,
            sourceID: sourceID,
            sourceName: sourceName,
            colorHex: colorHex,
            location: location?.isEmpty == true ? nil : location,
            notePreview: description?.isEmpty == true ? nil : description
        )
    }

    private static func parseICSDate(
        _ raw: String,
        params: [String: String],
        calendar: Calendar
    ) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tzid = params["TZID"], let timeZone = TimeZone(identifier: tzid) {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.dateFormat = "yyyyMMdd'T'HHmm"
            if let date = formatter.date(from: value) {
                return date
            }
        }

        if value.hasSuffix("Z") {
            let trimmed = String(value.dropLast())
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            return formatter.date(from: trimmed)
        }

        if value.count == 8 {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: value)
        }

        let localFormatter = DateFormatter()
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = calendar.timeZone
        localFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let date = localFormatter.date(from: value) {
            return date
        }
        localFormatter.dateFormat = "yyyyMMdd'T'HHmm"
        return localFormatter.date(from: value)
    }
}
