import Foundation

final class LocalTranscriptSearchService: QueryService, @unchecked Sendable {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let calendar: Calendar
    private let cache = NSCache<NSString, CachedDay>()

    init(paths: AppPaths, fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.paths = paths
        self.fileManager = fileManager
        self.calendar = calendar
        cache.countLimit = 60
    }

    func search(query: String, dayRange: ClosedRange<String>? = nil) async throws -> [QueryResult] {
        let keywords = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }

        guard !keywords.isEmpty else { return [] }

        let dayDirs = availableDays(in: dayRange)
        var results: [QueryResult] = []
        results.reserveCapacity(64)

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        for dayDir in dayDirs {
            let dayName = dayDir.lastPathComponent
            guard let transcript = loadTranscript(dayDir: dayDir, dayName: dayName) else { continue }

            for segment in transcript.segments {
                let lower = segment.text.lowercased()
                let matchCount = keywords.filter { lower.contains($0) }.count
                guard matchCount > 0 else { continue }

                let density = Double(matchCount) / Double(keywords.count)
                let recencyBonus = recencyScore(day: dayName)
                let relevance = density * 0.7 + recencyBonus * 0.3

                let result = QueryResult(
                    id: segment.id,
                    text: segment.text,
                    day: dayName,
                    timeLabel: timeFormatter.string(from: segment.startAt),
                    timeRange: DateInterval(start: segment.startAt, end: segment.endAt),
                    sourceFile: segment.sourceFile,
                    relevanceHint: relevance
                )
                results.append(result)
            }
        }

        results.sort { $0.relevanceHint > $1.relevanceHint }
        if results.count > 100 {
            results = Array(results.prefix(100))
        }
        return results
    }

    // MARK: - Private

    private func availableDays(in range: ClosedRange<String>?) -> [URL] {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: paths.transcriptsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var dayDirs = dirs.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir
        }

        if let range {
            dayDirs = dayDirs.filter { range.contains($0.lastPathComponent) }
        }

        dayDirs.sort { $0.lastPathComponent > $1.lastPathComponent }
        return dayDirs
    }

    private func loadTranscript(dayDir: URL, dayName: String) -> TranscriptDay? {
        let key = dayName as NSString
        if let cached = cache.object(forKey: key) {
            return cached.transcript
        }

        let jsonURL = dayDir.appendingPathComponent("day-transcript.json", isDirectory: false)
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = AppDateFormatter.parseEventTimestamp(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }

        guard let transcript = try? decoder.decode(TranscriptDay.self, from: data) else { return nil }
        cache.setObject(CachedDay(transcript: transcript), forKey: key)
        return transcript
    }

    private func recencyScore(day: String) -> Double {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: day) else { return 0 }
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 365
        return max(0, 1.0 - Double(daysAgo) / 365.0)
    }
}

private final class CachedDay: @unchecked Sendable {
    let transcript: TranscriptDay
    init(transcript: TranscriptDay) { self.transcript = transcript }
}
