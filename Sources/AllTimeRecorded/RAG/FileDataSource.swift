import Foundation

/// Data source that queries local files via Spotlight (NSMetadataQuery).
/// Falls back to LEANN's `files_index` if available.
///
/// Two retrieval paths:
/// 1. **Spotlight** — always available, queries system-wide file metadata.
///    Returns files whose name or content matches the query keywords.
/// 2. **LEANN files_index** — optional, deep content search via embeddings.
///    If the index exists, results from both paths are merged.
actor FileDataSource: DataSource {
    nonisolated let id = "files"
    nonisolated let displayName = "Local Files"
    nonisolated let requiresConsent = false

    private let bridge: (any LEANNBridging)?
    private let filesIndexName: String

    init(bridge: (any LEANNBridging)? = nil, filesIndexName: String = "files_index") {
        self.bridge = bridge
        self.filesIndexName = filesIndexName
    }

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        // Run Spotlight and LEANN in parallel
        async let spotlightResults = spotlightSearch(question: question, topK: topK)
        async let leannResults = leannSearch(question: question, topK: topK)

        let spotlight = await spotlightResults
        let leann = await leannResults

        // Merge, dedupe by file path, prefer LEANN results (deeper content match)
        var seen = Set<String>()
        var merged: [SourceChunk] = []

        for chunk in leann {
            if let uri = chunk.originURI {
                seen.insert(uri)
            }
            merged.append(chunk)
        }

        for chunk in spotlight {
            if let uri = chunk.originURI, seen.contains(uri) { continue }
            merged.append(chunk)
        }

        return Array(merged.prefix(topK))
    }

    // MARK: - Spotlight

    private func spotlightSearch(question: String, topK: Int) async -> [SourceChunk] {
        let keywords = CalendarDataSource.extractKeywords(from: question)
        guard !keywords.isEmpty else { return [] }

        // Run Spotlight on the main actor to satisfy NSMetadataQuery requirements
        return await MainActor.run {
            Self.spotlightSearchSync(keywords: keywords, topK: topK)
        }
    }

    /// Synchronous Spotlight search using mdfind subprocess (avoids NSMetadataQuery
    /// Sendable issues). Returns quickly with best-effort results.
    @MainActor
    private static func spotlightSearchSync(keywords: [String], topK: Int) -> [SourceChunk] {
        // Use mdfind as a simpler, synchronous alternative to NSMetadataQuery
        let queryString = keywords.joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        // mdfind has no -limit flag; we pipe through head instead
        process.arguments = ["-onlyin", NSHomeDirectory(), queryString]

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

        let paths = output.split(separator: "\n").map(String.init)
        var chunks: [SourceChunk] = []

        for path in paths.prefix(topK) {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent

            // Skip hidden files, caches, build artifacts
            let lowerPath = path.lowercased()
            let excludePatterns = [
                "/library/caches/", "/.build/", "/deriveddata/",
                "/.git/", "/node_modules/", "/.trash/",
                "/library/application support/com.apple",
            ]
            if excludePatterns.contains(where: { lowerPath.contains($0) }) {
                continue
            }

            let fm = FileManager.default
            let attrs = try? fm.attributesOfItem(atPath: path)
            let modDate = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? Int64 ?? 0

            let lowerName = name.lowercased()
            let hits = keywords.filter { lowerName.contains($0) }
            let score = max(Double(hits.count) / Double(max(keywords.count, 1)), 0.1)

            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short

            var body = "File: \(name)"
            body += "\nPath: \(path)"
            if fileSize > 0 {
                body += "\nSize: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))"
            }
            if let date = modDate {
                body += "\nModified: \(df.string(from: date))"
            }

            chunks.append(SourceChunk(
                id: "files#\(path.hashValue)",
                sourceID: "files",
                title: name,
                body: body,
                timestamp: modDate,
                originURI: url.absoluteString,
                score: score
            ))
        }

        return chunks
    }

    private static func metadataItemToChunk(_ item: NSMetadataItem, keywords: [String]) -> SourceChunk? {
        guard let path = item.value(forAttribute: kMDItemPath as String) as? String else {
            return nil
        }
        // Skip hidden files, caches, and build artifacts
        let lowerPath = path.lowercased()
        let excludePatterns = [
            "/library/caches/", "/.build/", "/deriveddata/",
            "/.git/", "/node_modules/", "/.trash/",
            "/library/application support/com.apple",
        ]
        if excludePatterns.contains(where: { lowerPath.contains($0) }) {
            return nil
        }

        let name = item.value(forAttribute: kMDItemDisplayName as String) as? String
            ?? (path as NSString).lastPathComponent
        let modDate = item.value(forAttribute: kMDItemFSContentChangeDate as String) as? Date
        let fileSize = item.value(forAttribute: kMDItemFSSize as String) as? Int64 ?? 0
        let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? "unknown"

        // Compute simple relevance based on keyword hits in filename
        let lowerName = name.lowercased()
        let hits = keywords.filter { lowerName.contains($0) }
        let score = Double(hits.count) / Double(max(keywords.count, 1))

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var body = "File: \(name)"
        body += "\nPath: \(path)"
        body += "\nType: \(contentType)"
        if fileSize > 0 {
            body += "\nSize: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))"
        }
        if let date = modDate {
            body += "\nModified: \(df.string(from: date))"
        }

        return SourceChunk(
            id: "files#\(path.hashValue)",
            sourceID: "files",
            title: name,
            body: body,
            timestamp: modDate,
            originURI: URL(fileURLWithPath: path).absoluteString,
            score: max(score, 0.1)
        )
    }

    // MARK: - LEANN fallback

    private func leannSearch(question: String, topK: Int) async -> [SourceChunk] {
        guard let bridge else { return [] }
        do {
            return try await bridge.search(index: filesIndexName, query: question, topK: topK)
        } catch {
            // Index may not exist
            return []
        }
    }
}
