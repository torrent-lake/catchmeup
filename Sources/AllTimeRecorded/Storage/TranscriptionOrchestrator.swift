import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

@MainActor
final class TranscriptionOrchestrator: TranscriptionScheduling {
    private let paths: AppPaths
    private let modelService: ModelAssetService
    private let runner: WhisperCppRunner
    private let fileManager: FileManager
    private let calendar: Calendar

    private var timer: Timer?
    private var isTranscribing = false
    private var stopped = false

    init(
        paths: AppPaths = AppPaths(),
        modelService: ModelAssetService,
        runner: WhisperCppRunner = WhisperCppRunner(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.paths = paths
        self.modelService = modelService
        self.runner = runner
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func start() {
        stopped = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: AppConstants.transcriptionPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        Task { @MainActor in
            await tick()
        }
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        guard !stopped, !isTranscribing else { return }
        guard isOnACPower(), isUserIdle() else { return }

        let pendingDays = pendingDayDirectories()
        guard !pendingDays.isEmpty else { return }

        // Do not auto-trigger large model download in the background.
        guard modelService.isLocalModelUsable else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        if case .ready = modelService.state {
            // Already ready.
        } else {
            await modelService.ensureModelReady()
        }
        guard case .ready(let modelPath) = modelService.state else { return }

        for dayDir in pendingDays {
            if stopped { return }
            await transcribeDay(dayDirectory: dayDir, modelPath: modelPath)
        }
    }

    private func pendingDayDirectories() -> [URL] {
        guard let dayDirs = try? fileManager.contentsOfDirectory(
            at: paths.audioRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let todayStart = calendar.startOfDay(for: Date())
        return dayDirs
            .filter { isDateDirectory($0) }
            .filter { dir in
                guard let day = parseDayDirectoryName(dir.lastPathComponent) else { return false }
                return day < todayStart
            }
            .filter { dir in
                let transcriptJSON = paths.transcriptsRoot
                    .appendingPathComponent(dir.lastPathComponent, isDirectory: true)
                    .appendingPathComponent("day-transcript.json", isDirectory: false)
                return !fileManager.fileExists(atPath: transcriptJSON.path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func transcribeDay(dayDirectory: URL, modelPath: String) async {
        let sourceFiles = sourceAudioFiles(in: dayDirectory)
        guard !sourceFiles.isEmpty else { return }

        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(128)

        for sourceFile in sourceFiles {
            let segmentStart = parseSegmentStart(fileURL: sourceFile, fallbackDayDirectory: dayDirectory)
            do {
                let part = try runner.transcribe(
                    fileURL: sourceFile,
                    modelURL: URL(fileURLWithPath: modelPath),
                    segmentStartAt: segmentStart
                )
                segments.append(contentsOf: part)
            } catch {
                continue
            }
        }
        guard !segments.isEmpty else { return }
        segments.sort { $0.startAt < $1.startAt }

        let dayFolder = paths.transcriptsRoot.appendingPathComponent(dayDirectory.lastPathComponent, isDirectory: true)
        try? fileManager.createDirectory(at: dayFolder, withIntermediateDirectories: true)

        let transcript = TranscriptDay(
            day: dayDirectory.lastPathComponent,
            modelID: modelService.modelID,
            generatedAt: Date(),
            languageMode: "native",
            segments: segments
        )
        writeJSON(transcript, to: dayFolder.appendingPathComponent("day-transcript.json", isDirectory: false))
        writeTXT(transcript, to: dayFolder.appendingPathComponent("day-transcript.txt", isDirectory: false))
    }

    private func sourceAudioFiles(in dayDirectory: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: dayDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let splitFiles = files
            .filter { $0.pathExtension == "m4a" && !$0.lastPathComponent.contains("__open") && $0.lastPathComponent != "daily-merged.m4a" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !splitFiles.isEmpty {
            return splitFiles
        }
        let merged = dayDirectory.appendingPathComponent("daily-merged.m4a", isDirectory: false)
        if fileManager.fileExists(atPath: merged.path) {
            return [merged]
        }
        return []
    }

    private func parseSegmentStart(fileURL: URL, fallbackDayDirectory: URL) -> Date {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let startToken = fileName.components(separatedBy: "__").first ?? ""
        if let parsed = AppDateFormatter.parseFileTimestamp(startToken) {
            return parsed
        }
        return parseDayDirectoryName(fallbackDayDirectory.lastPathComponent) ?? Date()
    }

    private func writeJSON(_ transcript: TranscriptDay, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(AppDateFormatter.eventTimestamp(date))
        }
        guard let data = try? encoder.encode(transcript) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func writeTXT(_ transcript: TranscriptDay, to url: URL) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"

        let lines = transcript.segments.map { segment in
            let start = formatter.string(from: segment.startAt)
            let end = formatter.string(from: segment.endAt)
            return "[\(start)-\(end)] \(segment.text)"
        }
        let content = lines.joined(separator: "\n")
        try? content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func isDateDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func parseDayDirectoryName(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func isOnACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String else {
                continue
            }
            if state == kIOPSACPowerValue {
                return true
            }
        }
        return false
    }

    private func isUserIdle() -> Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        return seconds >= AppConstants.transcriptionIdleSecondsThreshold
    }
}
