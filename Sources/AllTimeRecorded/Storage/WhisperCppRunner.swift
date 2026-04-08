import Foundation

enum WhisperCppRunnerError: LocalizedError {
    case cliNotFound
    case processFailed(String)
    case outputMissing
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "whisper-cli was not found."
        case .processFailed(let message):
            return "whisper-cli failed: \(message)"
        case .outputMissing:
            return "whisper-cli did not produce output JSON."
        case .conversionFailed:
            return "Failed to convert audio to WAV."
        }
    }
}

struct WhisperCppRunner {
    private let cliPath: String?
    private let additionalCLIPaths: [String]

    init(cliPath: String? = nil, additionalCLIPaths: [String] = []) {
        self.cliPath = cliPath
        if additionalCLIPaths.isEmpty {
            self.additionalCLIPaths = [
                AppPaths().modelsRoot.appendingPathComponent("whisper-cli", isDirectory: false).path
            ]
        } else {
            self.additionalCLIPaths = additionalCLIPaths
        }
    }

    func transcribe(
        fileURL: URL,
        modelURL: URL,
        segmentStartAt: Date
    ) async throws -> [TranscriptSegment] {
        guard let executable = resolveCLIPath() else {
            throw WhisperCppRunnerError.cliNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("alltimerecorded-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Convert M4A/AAC to WAV — whisper-cli only reads WAV
        let wavURL = tempDir.appendingPathComponent("input.wav")
        let convertStatus = try await runProcess(
            executable: "/usr/bin/afconvert",
            arguments: ["-f", "WAVE", "-d", "LEI16@16000", fileURL.path, wavURL.path]
        )
        guard convertStatus == 0 else {
            throw WhisperCppRunnerError.conversionFailed
        }

        let outputPrefix = tempDir.appendingPathComponent("output").path
        let status = try await runProcess(
            executable: executable,
            arguments: ["-m", modelURL.path, "-f", wavURL.path, "-oj", "-of", outputPrefix]
        )

        guard status == 0 else {
            throw WhisperCppRunnerError.processFailed("exit \(status)")
        }

        let jsonURL = URL(fileURLWithPath: outputPrefix + ".json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL) else {
            throw WhisperCppRunnerError.outputMissing
        }

        return try parseSegments(data: data, baseDate: segmentStartAt, sourceFile: fileURL.lastPathComponent)
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseSegments(data: Data, baseDate: Date, sourceFile: String) throws -> [TranscriptSegment] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Support both old format ("segments" with t0/t1)
        // and new format ("transcription" with offsets.from/to in ms)
        if let transcription = object["transcription"] as? [[String: Any]] {
            return parseNewFormat(transcription, baseDate: baseDate, sourceFile: sourceFile)
        }
        if let segments = object["segments"] as? [[String: Any]] {
            return parseOldFormat(segments, baseDate: baseDate, sourceFile: sourceFile)
        }
        return []
    }

    private func parseNewFormat(_ entries: [[String: Any]], baseDate: Date, sourceFile: String) -> [TranscriptSegment] {
        var output: [TranscriptSegment] = []
        output.reserveCapacity(entries.count)

        for entry in entries {
            let text = (entry["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }

            var t0: Double = 0
            var t1: Double = 0
            if let offsets = entry["offsets"] as? [String: Any] {
                t0 = (offsets["from"] as? NSNumber)?.doubleValue ?? 0
                t1 = (offsets["to"] as? NSNumber)?.doubleValue ?? t0
                // offsets are in milliseconds
                t0 /= 1000.0
                t1 /= 1000.0
            }
            t1 = max(t0, t1)

            output.append(
                TranscriptSegment(
                    id: UUID(),
                    startAt: baseDate.addingTimeInterval(t0),
                    endAt: baseDate.addingTimeInterval(t1),
                    text: text,
                    sourceFile: sourceFile,
                    sourceOffsetStart: t0,
                    sourceOffsetEnd: t1
                )
            )
        }
        return output
    }

    private func parseOldFormat(_ segments: [[String: Any]], baseDate: Date, sourceFile: String) -> [TranscriptSegment] {
        var output: [TranscriptSegment] = []
        output.reserveCapacity(segments.count)

        for segment in segments {
            let text = (segment["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            let t0Raw = (segment["t0"] as? NSNumber)?.doubleValue ?? 0
            let t1Raw = (segment["t1"] as? NSNumber)?.doubleValue ?? t0Raw
            let t0 = normalizeSeconds(t0Raw)
            let t1 = max(t0, normalizeSeconds(t1Raw))
            output.append(
                TranscriptSegment(
                    id: UUID(),
                    startAt: baseDate.addingTimeInterval(t0),
                    endAt: baseDate.addingTimeInterval(t1),
                    text: text,
                    sourceFile: sourceFile,
                    sourceOffsetStart: t0,
                    sourceOffsetEnd: t1
                )
            )
        }
        return output
    }

    private func normalizeSeconds(_ raw: Double) -> Double {
        if raw > 100_000 {
            return raw / 1_000
        }
        if raw > 1_000 {
            return raw / 100
        }
        return raw
    }

    private func resolveCLIPath() -> String? {
        if let cliPath, FileManager.default.isExecutableFile(atPath: cliPath) {
            return cliPath
        }
        let candidates = [
            additionalCLIPaths[0],
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/usr/bin/whisper-cli",
        ] + additionalCLIPaths.dropFirst()
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
