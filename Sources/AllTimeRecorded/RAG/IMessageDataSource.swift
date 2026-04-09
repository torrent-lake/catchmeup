import Foundation

/// Data source that queries iMessage history directly from macOS's chat.db.
/// No LEANN needed — we query SQLite directly for keyword matching.
///
/// The iMessage database lives at ~/Library/Messages/chat.db and uses
/// Apple's "Core Data timestamp" format (nanoseconds since 2001-01-01).
actor IMessageDataSource: DataSource {
    nonisolated let id = "imessage"
    nonisolated let displayName = "iMessage"
    nonisolated let requiresConsent = true

    private static let chatDBPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Library/Messages/chat.db"
    }()

    /// Apple Core Data epoch: 2001-01-01 00:00:00 UTC
    private static let coreDataEpoch: TimeInterval = 978307200

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        let dbPath = Self.chatDBPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let keywords = CalendarDataSource.extractKeywords(from: question)
        guard !keywords.isEmpty else { return [] }

        // Build SQL WHERE clause for keyword matching
        let conditions = keywords.map { kw in
            "m.text LIKE '%\(kw.replacingOccurrences(of: "'", with: "''"))%'"
        }
        let whereClause = conditions.joined(separator: " OR ")

        let sql = """
        SELECT
            m.ROWID,
            m.text,
            m.date,
            m.is_from_me,
            COALESCE(h.id, 'Unknown') as handle_id,
            c.display_name as chat_name
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        LEFT JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.text IS NOT NULL
            AND length(m.text) > 5
            AND (\(whereClause))
        ORDER BY m.date DESC
        LIMIT \(topK * 2)
        """

        return executeSQLQuery(dbPath: dbPath, sql: sql, keywords: keywords, topK: topK)
    }

    /// Also provides a method to get recent messages for context density
    /// (no keyword filter, just recent messages for the heatmap).
    func recentMessages(from start: Date, to end: Date, limit: Int = 200) async -> [SourceChunk] {
        let dbPath = Self.chatDBPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let startNs = Int64((start.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)
        let endNs = Int64((end.timeIntervalSince1970 - Self.coreDataEpoch) * 1_000_000_000)

        let sql = """
        SELECT
            m.ROWID,
            m.text,
            m.date,
            m.is_from_me,
            COALESCE(h.id, 'Unknown') as handle_id,
            c.display_name as chat_name
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        LEFT JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.text IS NOT NULL
            AND length(m.text) > 5
            AND m.date >= \(startNs)
            AND m.date <= \(endNs)
        ORDER BY m.date DESC
        LIMIT \(limit)
        """

        return executeSQLQuery(dbPath: dbPath, sql: sql, keywords: [], topK: limit)
    }

    private func executeSQLQuery(dbPath: String, sql: String, keywords: [String], topK: Int) -> [SourceChunk] {
        // Use sqlite3 subprocess to avoid linking SQLite directly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "-separator", "\t", sql]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var chunks: [SourceChunk] = []
        let lines = output.split(separator: "\n")

        for line in lines.prefix(topK) {
            let cols = line.split(separator: "\t", maxSplits: 5).map(String.init)
            guard cols.count >= 5 else { continue }

            let rowID = cols[0]
            let text = cols[1]
            let dateNs = Int64(cols[2]) ?? 0
            let isFromMe = cols[3] == "1"
            let handleID = cols[4]
            let chatName = cols.count > 5 ? cols[5] : ""

            // Convert Apple Core Data timestamp to Date
            let timestamp = Date(timeIntervalSince1970: Double(dateNs) / 1_000_000_000 + Self.coreDataEpoch)

            let sender = isFromMe ? "Me" : handleID
            let context = chatName.isEmpty ? sender : "\(chatName) — \(sender)"

            // Compute relevance
            let lowerText = text.lowercased()
            let hits = keywords.filter { lowerText.contains($0) }
            let score = keywords.isEmpty ? 0.5 : Double(hits.count) / Double(max(keywords.count, 1))

            chunks.append(SourceChunk(
                id: "imessage#\(rowID)",
                sourceID: "imessage",
                title: "\(context): \(String(text.prefix(50)))",
                body: "[\(sender)] \(text)",
                timestamp: timestamp,
                originURI: "imessage://\(handleID)",
                score: max(score, 0.1)
            ))
        }

        return chunks
    }
}
