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
        // Collect open system audio files keyed by their timestamp prefix
        var openSysFiles: [String: URL] = [:]

        // First pass: discover all __open files
        var openMicFiles: [(url: URL, stamp: String)] = []
        var allURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "m4a",
                  fileURL.lastPathComponent.contains("__open")
            else {
                continue
            }
            allURLs.append(fileURL)
        }

        for fileURL in allURLs {
            let name = fileURL.deletingPathExtension().lastPathComponent
            let stamp = name.components(separatedBy: "__").first ?? ""
            if name.contains("_sys") {
                openSysFiles[stamp] = fileURL
            } else {
                openMicFiles.append((url: fileURL, stamp: stamp))
            }
        }

        for (micURL, stamp) in openMicFiles {
            let startAt = AppDateFormatter.parseFileTimestamp(stamp) ?? currentDate
            let values = try? micURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let endAt = max(startAt, values?.contentModificationDate ?? currentDate)
            let bytes = Int64(values?.fileSize ?? 0)
            let micFinalName = "\(AppDateFormatter.fileTimestamp(startAt))__\(AppDateFormatter.fileTimestamp(endAt))_mic.m4a"
            let micFinalURL = micURL.deletingLastPathComponent().appendingPathComponent(micFinalName, isDirectory: false)
            try? fileManager.moveItem(at: micURL, to: micFinalURL)

            var systemFinalURL: URL? = nil
            var systemBytes: Int64 = 0
            if let sysURL = openSysFiles[stamp] {
                let sysFinalName = "\(AppDateFormatter.fileTimestamp(startAt))__\(AppDateFormatter.fileTimestamp(endAt))_sys.m4a"
                let sysFinalURL = sysURL.deletingLastPathComponent().appendingPathComponent(sysFinalName, isDirectory: false)
                try? fileManager.moveItem(at: sysURL, to: sysFinalURL)
                if fileManager.fileExists(atPath: sysFinalURL.path) {
                    systemFinalURL = sysFinalURL
                    let sysValues = try? sysFinalURL.resourceValues(forKeys: [.fileSizeKey])
                    systemBytes = Int64(sysValues?.fileSize ?? 0)
                }
            }

            let segment = RecordingSegment(
                id: UUID(),
                startAt: startAt,
                endAt: endAt,
                fileURL: fileManager.fileExists(atPath: micFinalURL.path) ? micFinalURL : micURL,
                bytes: bytes,
                sourceDeviceID: 0,
                systemFileURL: systemFinalURL,
                systemBytes: systemBytes
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
