import Foundation

final class EventStore {
    private struct StoredEvent: Codable {
        enum EventType: String, Codable {
            case segment
            case gap
            case loudness
        }

        let type: EventType
        let recordedAt: Date
        let segment: RecordingSegment?
        let gap: GapEvent?
        let loudness: LoudnessEvent?
    }

    private let paths: AppPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) throws {
        self.paths = paths
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(AppDateFormatter.eventTimestamp(date))
        }

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = AppDateFormatter.parseEventTimestamp(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }

        try paths.ensureBaseDirectories()
    }

    func loadTimelineData() -> (segments: [RecordingSegment], gaps: [GapEvent], loudness: [LoudnessEvent]) {
        guard let data = try? Data(contentsOf: paths.eventsFileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return ([], [], [])
        }

        var segments: [RecordingSegment] = []
        var gaps: [GapEvent] = []
        var loudness: [LoudnessEvent] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }
            guard let event = try? decoder.decode(StoredEvent.self, from: lineData) else { continue }
            switch event.type {
            case .segment:
                if let segment = event.segment {
                    segments.append(segment)
                }
            case .gap:
                if let gap = event.gap {
                    gaps.append(gap)
                }
            case .loudness:
                if let level = event.loudness {
                    loudness.append(level)
                }
            }
        }
        return (
            segments.sorted { $0.startAt < $1.startAt },
            gaps.sorted { $0.startAt < $1.startAt },
            loudness.sorted { $0.sampledAt < $1.sampledAt }
        )
    }

    func appendSegment(_ segment: RecordingSegment) {
        append(
            StoredEvent(
                type: .segment,
                recordedAt: Date(),
                segment: segment,
                gap: nil,
                loudness: nil
            )
        )
    }

    func appendGap(_ gap: GapEvent) {
        append(
            StoredEvent(
                type: .gap,
                recordedAt: Date(),
                segment: nil,
                gap: gap,
                loudness: nil
            )
        )
    }

    func appendLoudness(_ event: LoudnessEvent) {
        append(
            StoredEvent(
                type: .loudness,
                recordedAt: Date(),
                segment: nil,
                gap: nil,
                loudness: event
            )
        )
    }

    func markLaunchUnclean() {
        if let data = "unclean".data(using: .utf8) {
            try? data.write(to: paths.lifecycleFileURL, options: .atomic)
        }
    }

    func previousLaunchWasClean() -> Bool {
        guard let data = try? Data(contentsOf: paths.lifecycleFileURL),
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return true
        }
        return value == "clean"
    }

    func markCleanShutdown() {
        if let data = "clean".data(using: .utf8) {
            try? data.write(to: paths.lifecycleFileURL, options: .atomic)
        }
    }

    func recoverOpenSegments(currentDate: Date = Date()) -> [RecordingSegment] {
        guard let enumerator = fileManager.enumerator(at: paths.audioRoot, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return []
        }

        var recovered: [RecordingSegment] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "m4a",
                  fileURL.lastPathComponent.contains("__open")
            else {
                continue
            }

            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let startStamp = fileName.components(separatedBy: "__").first ?? ""
            let startAt = AppDateFormatter.parseFileTimestamp(startStamp) ?? currentDate
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let endAt = max(startAt, values?.contentModificationDate ?? currentDate)
            let bytes = Int64(values?.fileSize ?? 0)
            let finalName = "\(AppDateFormatter.fileTimestamp(startAt))__\(AppDateFormatter.fileTimestamp(endAt)).m4a"
            let finalURL = fileURL.deletingLastPathComponent().appendingPathComponent(finalName, isDirectory: false)

            try? fileManager.moveItem(at: fileURL, to: finalURL)

            let segment = RecordingSegment(
                id: UUID(),
                startAt: startAt,
                endAt: endAt,
                fileURL: finalURL,
                bytes: bytes,
                sourceDeviceID: 0
            )
            appendSegment(segment)
            recovered.append(segment)
        }

        return recovered.sorted { $0.startAt < $1.startAt }
    }

    private func append(_ event: StoredEvent) {
        guard let data = try? encoder.encode(event), var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        guard let handle = try? FileHandle(forWritingTo: paths.eventsFileURL),
              let lineData = line.data(using: .utf8)
        else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: lineData)
    }
}
