import Foundation

enum WhisperCppRunnerError: LocalizedError {
    case cliNotFound
    case processFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "whisper-cli was not found."
        case .processFailed(let message):
            return "whisper-cli failed: \(message)"
        case .outputMissing:
            return "whisper-cli did not produce output JSON."
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
    ) throws -> [TranscriptSegment] {
        guard let executable = resolveCLIPath() else {
            throw WhisperCppRunnerError.cliNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("alltimerecorded-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPrefix = tempDir.appendingPathComponent("output").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-m", modelURL.path,
            "-f", fileURL.path,
            "-oj",
            "-of", outputPrefix,
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw WhisperCppRunnerError.processFailed(message)
        }

        let jsonURL = URL(fileURLWithPath: outputPrefix + ".json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL) else {
            throw WhisperCppRunnerError.outputMissing
        }

        return try parseSegments(data: data, baseDate: segmentStartAt, sourceFile: fileURL.lastPathComponent)
    }

    private func parseSegments(data: Data, baseDate: Date, sourceFile: String) throws -> [TranscriptSegment] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = object["segments"] as? [[String: Any]] else {
            return []
        }

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
