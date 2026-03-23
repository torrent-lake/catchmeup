import AVFoundation
import Foundation

actor DailyAudioCompactor {
    private let audioRoot: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    private let encoder: DailyMergedEncoder
    private var compacting = false

    init(
        audioRoot: URL,
        calendar: Calendar = .current,
        encoder: DailyMergedEncoder = DailyMergedEncoder()
    ) {
        self.audioRoot = audioRoot
        self.fileManager = .default
        self.calendar = calendar
        self.encoder = encoder
    }

    func compactFinishedDays(referenceDate: Date = Date()) async {
        // Historical compaction is intentionally disabled to preserve timestamped segments.
        _ = referenceDate
    }

    private func compact(dayDirectory: URL) async {
        let mergedURL = dayDirectory.appendingPathComponent("daily-merged.m4a", isDirectory: false)
        let tempURL = dayDirectory.appendingPathComponent("daily-merged.tmp.m4a", isDirectory: false)
        try? fileManager.removeItem(at: tempURL)

        let sourceFiles = compactableSegmentFiles(in: dayDirectory, excluding: mergedURL)
        guard sourceFiles.count > 1 else { return }

        let composition = AVMutableComposition()
        guard let targetTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return
        }

        var cursor = CMTime.zero
        for sourceURL in sourceFiles {
            let asset = AVURLAsset(url: sourceURL)
            guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
                continue
            }
            guard let duration = try? await asset.load(.duration), duration.isNumeric, duration > .zero else {
                continue
            }
            try? targetTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: cursor)
            cursor = cursor + duration
        }

        guard cursor > .zero else {
            return
        }

        do {
            try await encoder.encode(composition: composition, to: tempURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return
        }
        guard await isValidMergedOutput(tempURL, expectedDuration: cursor) else {
            try? fileManager.removeItem(at: tempURL)
            return
        }

        if fileManager.fileExists(atPath: mergedURL.path) {
            try? fileManager.removeItem(at: mergedURL)
        }
        try? fileManager.moveItem(at: tempURL, to: mergedURL)

        for sourceURL in sourceFiles {
            try? fileManager.removeItem(at: sourceURL)
        }
    }

    private func isValidMergedOutput(_ url: URL, expectedDuration: CMTime) async -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value > 0
        else {
            return false
        }

        guard expectedDuration.isNumeric, expectedDuration > .zero else {
            return false
        }

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric, duration > .zero else {
            return false
        }

        let ratio = duration.seconds / expectedDuration.seconds
        return ratio >= 0.99
    }

    private func compactableSegmentFiles(in dayDirectory: URL, excluding mergedURL: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: dayDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { fileURL in
                fileURL.pathExtension == "m4a"
                    && fileURL.lastPathComponent != mergedURL.lastPathComponent
                    && !fileURL.lastPathComponent.contains("__open")
            }
            .sorted(by: { lhs, rhs in
                fileSortKey(lhs) < fileSortKey(rhs)
            })
    }

    private func fileSortKey(_ fileURL: URL) -> String {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let startStamp = fileName.components(separatedBy: "__").first ?? fileName
        return startStamp
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
}
