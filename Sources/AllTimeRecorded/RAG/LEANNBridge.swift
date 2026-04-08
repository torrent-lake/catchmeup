import Foundation

/// Subprocess-backed LEANN bridge. Launches the `leann` CLI as a child process
/// and parses its output.
///
/// Binary resolution strategy (in order):
///   1. `UserDefaults.standard.string(forKey: "CatchMeUp.leannBinaryPath")` — user override
///   2. `/Users/yizhi/leann/.venv/bin/leann` — canonical dev install
///   3. `$HOME/.local/bin/leann` — `uv tool install` default
///   4. `/opt/homebrew/bin/leann` — Homebrew
///   5. `/usr/local/bin/leann` — Intel Homebrew / manual install
///
/// Phase 1 scope: single `searchRaw` call works end-to-end. The structured
/// parser is a best-effort line-by-line split returning one chunk per result
/// block. Phase 2+ will switch to `--format json` once LEANN ships it.
actor LEANNBridge: LEANNBridging {
    enum Failure: LocalizedError {
        case binaryNotFound(tried: [String])
        case nonZeroExit(code: Int32, stderr: String)
        case unreadableOutput

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let tried):
                return "Could not find the `leann` binary. Tried: \(tried.joined(separator: ", "))"
            case .nonZeroExit(let code, let stderr):
                return "leann exited with code \(code). stderr: \(stderr)"
            case .unreadableOutput:
                return "Could not decode leann stdout as UTF-8."
            }
        }
    }

    /// Candidate binary paths, checked in order at first use.
    private static let candidatePaths: [String] = [
        "/Users/yizhi/leann/.venv/bin/leann",
        NSString("~/.local/bin/leann").expandingTildeInPath,
        "/opt/homebrew/bin/leann",
        "/usr/local/bin/leann",
    ]

    private static let userDefaultsOverrideKey = "CatchMeUp.leannBinaryPath"

    /// Cached resolved path. Computed once per actor instance.
    private var resolvedBinary: URL?

    init() {}

    // MARK: - LEANNBridging

    func listIndices() async throws -> [String] {
        let out = try await runCapturing(arguments: ["list"])
        // Parse lines that look like "      • 📁 <name>" or "  📄 <name>".
        var names: [String] = []
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("•") else { continue }
            // e.g. "• 📁 mail_index ✅" → "mail_index"
            let afterBullet = trimmed.split(separator: "•", maxSplits: 1).last.map(String.init) ?? ""
            let afterIcon = afterBullet
                .drop { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }
            // Take until first whitespace.
            let name = afterIcon.prefix { !$0.isWhitespace }
            if !name.isEmpty {
                names.append(String(name))
            }
        }
        return names
    }

    func search(index: String, query: String, topK: Int) async throws -> [SourceChunk] {
        let raw = try await searchRaw(index: index, query: query, topK: topK)
        return parseSearchOutput(raw: raw, sourceID: indexToSourceID(index), indexName: index)
    }

    func searchRaw(index: String, query: String, topK: Int) async throws -> String {
        try await runCapturing(arguments: [
            "search",
            index,
            query,
            "--top-k",
            "\(topK)",
        ])
    }

    // MARK: - Subprocess plumbing

    private func resolveBinary() throws -> URL {
        if let cached = resolvedBinary {
            return cached
        }
        var tried: [String] = []
        if let override = UserDefaults.standard.string(forKey: Self.userDefaultsOverrideKey) {
            tried.append(override)
            if FileManager.default.isExecutableFile(atPath: override) {
                let url = URL(fileURLWithPath: override)
                resolvedBinary = url
                return url
            }
        }
        for path in Self.candidatePaths {
            tried.append(path)
            if FileManager.default.isExecutableFile(atPath: path) {
                let url = URL(fileURLWithPath: path)
                resolvedBinary = url
                return url
            }
        }
        throw Failure.binaryNotFound(tried: tried)
    }

    private func runCapturing(arguments: [String], timeoutSeconds: TimeInterval = 15) async throws -> String {
        let binary = try resolveBinary()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments

            // Inherit env but clear any stale venv activation; leann shim handles its own venv.
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "VIRTUAL_ENV")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutCollector = PipeCollector(pipe: stdoutPipe)
            let stderrCollector = PipeCollector(pipe: stderrPipe)
            stdoutCollector.start()
            stderrCollector.start()

            let resumed = Atomic(false)

            process.terminationHandler = { proc in
                stdoutCollector.stop()
                stderrCollector.stop()
                guard resumed.compareExchange(expected: false, desired: true) else { return }
                let outData = stdoutCollector.collected()
                let errData = stderrCollector.collected()
                if proc.terminationStatus == 0 {
                    if let text = String(data: outData, encoding: .utf8) {
                        continuation.resume(returning: text)
                    } else {
                        continuation.resume(throwing: Failure.unreadableOutput)
                    }
                } else {
                    let errText = String(data: errData, encoding: .utf8) ?? "<non-utf8 stderr>"
                    continuation.resume(throwing: Failure.nonZeroExit(code: proc.terminationStatus, stderr: errText))
                }
            }

            do {
                try process.run()
            } catch {
                guard resumed.compareExchange(expected: false, desired: true) else { return }
                continuation.resume(throwing: error)
                return
            }

            // Timeout guard.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning {
                    process.terminate()
                    if resumed.compareExchange(expected: false, desired: true) {
                        continuation.resume(throwing: Failure.nonZeroExit(code: -1, stderr: "timeout after \(timeoutSeconds)s"))
                    }
                }
            }
        }
    }

    // MARK: - Parsing (best-effort)

    /// Parse `leann search` stdout into a list of `SourceChunk`. The CLI's
    /// current output is human-readable and not fully stable — this parser is
    /// deliberately loose and returns whatever it can extract. Each non-empty
    /// paragraph becomes a chunk.
    nonisolated func parseSearchOutput(raw: String, sourceID: String, indexName: String) -> [SourceChunk] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var chunks: [SourceChunk] = []
        var currentBody: [String] = []
        var currentScore: Double = 0
        var chunkIndex = 0

        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                let title = String(body.prefix(60))
                chunks.append(SourceChunk(
                    id: "\(sourceID)#\(indexName)-\(chunkIndex)",
                    sourceID: sourceID,
                    title: title,
                    body: body,
                    timestamp: nil,
                    originURI: nil,
                    score: currentScore
                ))
                chunkIndex += 1
            }
            currentBody = []
            currentScore = 0
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Heuristic: lines starting with a digit followed by "." or "]" or containing
            // "score" often delimit a new result.
            let isResultHeader = trimmed.range(of: #"^\d+[.\])]"#, options: .regularExpression) != nil
                || trimmed.localizedCaseInsensitiveContains("score")
            if isResultHeader && !currentBody.isEmpty {
                flush()
            }
            if let scoreRange = trimmed.range(of: #"[-+]?\d+\.\d+"#, options: .regularExpression),
               trimmed.localizedCaseInsensitiveContains("score") {
                currentScore = Double(trimmed[scoreRange]) ?? currentScore
            }
            if !trimmed.isEmpty {
                currentBody.append(trimmed)
            }
        }
        flush()

        return chunks
    }

    private nonisolated func indexToSourceID(_ index: String) -> String {
        if index.contains("mail") { return "mail" }
        if index.contains("wechat") { return "wechat" }
        if index.contains("transcript") { return "transcripts" }
        if index.contains("file") { return "files" }
        return index
    }
}

// MARK: - Subprocess helpers

/// Minimal atomic flag used to guarantee a single continuation resume.
private final class Atomic: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ initial: Bool) { self.value = initial }

    func compareExchange(expected: Bool, desired: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value == expected {
            value = desired
            return true
        }
        return false
    }
}

/// Collects output from a `Pipe` into a buffer. Read on a background thread so
/// the subprocess doesn't block on a full pipe buffer.
private final class PipeCollector: @unchecked Sendable {
    private let pipe: Pipe
    private let lock = NSLock()
    private var buffer = Data()
    private var reading = true

    init(pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty {
                self.pipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            self.lock.lock()
            self.buffer.append(chunk)
            self.lock.unlock()
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        reading = false
        lock.unlock()
    }

    func collected() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
