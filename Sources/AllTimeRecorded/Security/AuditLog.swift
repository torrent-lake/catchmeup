import Foundation

/// Append-only audit log. Every query, injection block, refusal, answer,
/// and feedback event is persisted to JSONL for rubric traceability and
/// production hit rate calculation.
///
/// Thread-safe: uses an actor for serialization.
actor AuditLog {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func append(_ entry: AuditEntry) {
        do {
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                handle.write(lineData)
            }
        } catch {
            FileHandle.standardError.write(
                Data("[AuditLog] write failed: \(error)\n".utf8)
            )
        }
    }

    /// Read recent entries (for Settings → Audit tab).
    func recentEntries(limit: Int = 100) -> [AuditEntry] {
        guard let data = fileManager.contents(atPath: fileURL.path),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        let lines = content.split(separator: "\n").suffix(limit)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return lines.compactMap { line in
            try? decoder.decode(AuditEntry.self, from: Data(line.utf8))
        }
    }

    /// Compute production hit rate from recent feedback entries.
    func productionHitRate(days: Int = 7) -> Double? {
        let entries = recentEntries(limit: 1000)
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let feedback = entries.filter {
            $0.kind == .feedback && $0.timestamp > cutoff
        }
        guard !feedback.isEmpty else { return nil }
        let positive = feedback.filter { $0.userRating == .thumbsUp }.count
        return Double(positive) / Double(feedback.count)
    }
}

struct AuditEntry: Codable, Sendable {
    let timestamp: Date
    let kind: Kind
    let questionHash: String?
    let sourcesConsulted: [String]?
    let chunkIDs: [String]?
    let model: String?
    let durationMs: Int?
    let userRating: Rating?
    let detail: String?

    enum Kind: String, Codable, Sendable {
        case query
        case injectionBlocked = "injection_blocked"
        case refusal
        case answer
        case feedback
    }

    enum Rating: String, Codable, Sendable {
        case thumbsUp = "up"
        case thumbsDown = "down"
        case wrongSource = "wrong_source"
    }

    static func queryEntry(
        question: String,
        sources: [String],
        model: String?,
        durationMs: Int
    ) -> AuditEntry {
        AuditEntry(
            timestamp: Date(),
            kind: .query,
            questionHash: Self.hash(question),
            sourcesConsulted: sources,
            chunkIDs: nil,
            model: model,
            durationMs: durationMs,
            userRating: nil,
            detail: nil
        )
    }

    static func feedbackEntry(
        questionHash: String,
        rating: Rating
    ) -> AuditEntry {
        AuditEntry(
            timestamp: Date(),
            kind: .feedback,
            questionHash: questionHash,
            sourcesConsulted: nil,
            chunkIDs: nil,
            model: nil,
            durationMs: nil,
            userRating: rating,
            detail: nil
        )
    }

    private static func hash(_ text: String) -> String {
        var hasher = Hasher()
        hasher.combine(text)
        return String(format: "%08x", abs(hasher.finalize()))
    }
}
