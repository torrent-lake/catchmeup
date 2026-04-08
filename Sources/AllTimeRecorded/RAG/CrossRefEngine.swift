import Foundation

/// Parallel multi-source retrieval + merge + rerank.
///
/// Slice 2 scope: structured as N-source fanout, but the default wiring in
/// `AppDelegate` only passes one source (`MailDataSource`). Slice 3 adds
/// `WeChatDataSource`, `TranscriptDataSource`, `FilesDataSource` to the
/// `defaultSources` list in `AppDelegate` with no engine changes required.
///
/// Rerank strategy (Phase 2 minimal):
///   - Start with each chunk's raw LEANN score (`chunk.score`).
///   - Apply a small recency bonus: chunks with a more recent `timestamp`
///     get a modest boost.
///   - Apply a source-diversity penalty: once a source has already
///     contributed `ceil(budget / sources)` chunks, subsequent chunks from
///     the same source get a diminishing multiplier. This prevents one
///     very-chatty source from swamping the final prompt.
///   - Dedupe by chunk `id` first (cheap), then by 7-gram shingle hash of
///     the body (catches near-duplicates that LEANN returns from
///     overlapping chunks in the same underlying doc).
///   - Cap the final list at `budgetChunks`.
actor CrossRefEngine {

    /// Gather and rerank chunks for a question.
    ///
    /// - Parameters:
    ///   - question: the user's sanitized query.
    ///   - sources: data sources to fan out to.
    ///   - topKPerSource: how many chunks to request from each source.
    ///   - budgetChunks: hard cap on the number of reranked chunks returned.
    ///   - deadline: best-effort deadline. Sources that don't respond in
    ///     time are silently dropped with a warning log.
    /// - Returns: up to `budgetChunks` reranked chunks, ordered by
    ///   descending fused score. Never throws — failing sources are dropped.
    func gather(
        question: String,
        sources: [any DataSource],
        topKPerSource: Int,
        budgetChunks: Int,
        deadline: Date
    ) async -> [SourceChunk] {
        guard !sources.isEmpty else { return [] }

        // 1. Parallel fanout with deadline.
        let collected = await withTaskGroup(of: [SourceChunk].self) { group in
            for source in sources {
                group.addTask {
                    do {
                        // Simple deadline enforcement: run the source's query
                        // under an async throwing timeout. If the deadline is
                        // in the past we short-circuit.
                        let remaining = deadline.timeIntervalSinceNow
                        if remaining <= 0 {
                            return []
                        }
                        let result = try await withThrowingTaskGroup(of: [SourceChunk].self) { inner in
                            inner.addTask {
                                try await source.query(question: question, topK: topKPerSource)
                            }
                            inner.addTask {
                                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                                return []
                            }
                            let first = try await inner.next() ?? []
                            inner.cancelAll()
                            return first
                        }
                        return result
                    } catch {
                        // A failing source is dropped, not fatal. Log to
                        // stderr so the user/dev can diagnose without
                        // breaking the query.
                        FileHandle.standardError.write(
                            Data("[CrossRefEngine] source \(source.id) failed: \(error)\n".utf8)
                        )
                        return []
                    }
                }
            }
            var all: [SourceChunk] = []
            for await perSource in group {
                all.append(contentsOf: perSource)
            }
            return all
        }

        // 2. Dedupe by id, then by shingle hash.
        var seenIDs = Set<String>()
        var seenShingles = Set<Int>()
        var deduped: [SourceChunk] = []
        for chunk in collected {
            if !seenIDs.insert(chunk.id).inserted { continue }
            let shingle = Self.shingleHash(chunk.body)
            if !seenShingles.insert(shingle).inserted { continue }
            deduped.append(chunk)
        }

        // 3. Rerank.
        let sourceCount = max(1, sources.count)
        let perSourceBudget = Int((Double(budgetChunks) / Double(sourceCount)).rounded(.up))
        var sourceCounts: [String: Int] = [:]

        let scored: [(chunk: SourceChunk, fused: Double)] = deduped.map { chunk in
            var score = chunk.score

            // Recency bonus: up to +0.2 for content from the last 7 days,
            // decaying to 0 by 1 year old.
            if let ts = chunk.timestamp {
                let ageDays = max(0, -ts.timeIntervalSinceNow / 86_400)
                if ageDays < 7 {
                    score += 0.2
                } else if ageDays < 365 {
                    score += 0.2 * (1.0 - ageDays / 365.0)
                }
            }

            return (chunk, score)
        }

        // Apply source-diversity penalty via a stable sort + walk.
        let sortedByRaw = scored.sorted { $0.fused > $1.fused }
        var penalized: [(chunk: SourceChunk, fused: Double)] = []
        for entry in sortedByRaw {
            let count = sourceCounts[entry.chunk.sourceID, default: 0]
            let penalty: Double
            if count < perSourceBudget {
                penalty = 0
            } else {
                // Beyond the per-source budget, penalize subsequent chunks
                // from the same source. Multiplier shrinks with each extra.
                penalty = 0.15 * Double(count - perSourceBudget + 1)
            }
            let fusedFinal = entry.fused - penalty
            sourceCounts[entry.chunk.sourceID] = count + 1
            penalized.append((entry.chunk, fusedFinal))
        }

        let final = penalized.sorted { $0.fused > $1.fused }
        return Array(final.prefix(budgetChunks).map(\.chunk))
    }

    /// 7-gram shingle hash for near-duplicate detection. Cheap: takes the
    /// first 200 chars of the body, splits into 7-grams on whitespace, and
    /// hashes into a single Int. Not cryptographic — collision rate is
    /// acceptable for dedup within a single retrieval.
    nonisolated static func shingleHash(_ text: String) -> Int {
        let tokens = text
            .prefix(400)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let tokenList = Array(tokens)
        guard tokenList.count >= 7 else {
            return tokenList.joined(separator: " ").hashValue
        }
        var hasher = Hasher()
        for i in 0..<min(tokenList.count - 6, 30) {
            let shingle = tokenList[i..<(i + 7)].joined(separator: " ")
            hasher.combine(shingle)
        }
        return hasher.finalize()
    }
}
