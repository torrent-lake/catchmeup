import Foundation

/// A single on-demand question-and-answer turn. Owns the whole pipeline for
/// one user question: retrieve → scrub → compose → stream → validate.
///
/// Design notes:
/// - This is an `actor` so multiple concurrent sessions don't step on each
///   other (e.g., fast typers submitting before the previous answer finishes).
/// - The session does not retain conversation history — each `ask` is
///   independent. Multi-turn chat context is a Phase 3+ feature.
/// - Emits an `AsyncThrowingStream<AgentEvent, Error>` rather than returning
///   a final answer, so the UI can stream tokens live and show retrieval
///   progress before the LLM call even starts.
/// - Slice 2 scope: mail-only retrieval, no guardrail scrubbing (Phase 3
///   adds `GuardrailGate`), no consent gate, no audit log entry. The
///   pipeline stages exist as method calls so later slices can drop in
///   those pieces without rewriting the control flow.
actor AgentSession {
    private let llm: any LLMClient
    private let crossRef: CrossRefEngine
    private let composer: PromptComposer
    private let defaultSources: [any DataSource]

    init(
        llm: any LLMClient,
        crossRef: CrossRefEngine,
        composer: PromptComposer = PromptComposer(),
        defaultSources: [any DataSource]
    ) {
        self.llm = llm
        self.crossRef = crossRef
        self.composer = composer
        self.defaultSources = defaultSources
    }

    /// Ask a single question. Returns an event stream the UI consumes.
    ///
    /// Lifecycle of events:
    /// 1. `.started(question:)` — the session accepted the question.
    /// 2. `.retrieving(sources:)` — which data sources are being queried.
    /// 3. `.retrieved(chunks:)` — the reranked top chunks that will be cited.
    /// 4. Zero or more `.textDelta(String)` — streaming tokens from the LLM.
    /// 5. `.complete(final: citedChunks:)` — the final answer + its sources.
    ///
    /// If `sources` is nil, the session uses its `defaultSources`.
    nonisolated func ask(
        question: String,
        sources overrideSources: [any DataSource]? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let sources: [any DataSource]
                    if let overrideSources {
                        sources = overrideSources
                    } else {
                        sources = await self.defaultSources
                    }
                    let llm = await self.llm
                    let crossRef = await self.crossRef
                    let composer = await self.composer

                    // 1. Sanitize user input (Slice 2: length cap + control char strip).
                    let sanitized = Self.sanitizeInput(question)
                    guard !sanitized.isEmpty else {
                        continuation.finish(throwing: AgentSessionError.emptyQuestion)
                        return
                    }

                    continuation.yield(.started(question: sanitized))

                    // 2. Announce retrieval target.
                    let sourceIDs = sources.map(\.id)
                    continuation.yield(.retrieving(sourceIDs: sourceIDs))

                    // 3. Retrieve via CrossRefEngine.
                    let chunks = await crossRef.gather(
                        question: sanitized,
                        sources: sources,
                        topKPerSource: 5,
                        budgetChunks: 12,
                        deadline: Date().addingTimeInterval(10)
                    )

                    if Task.isCancelled {
                        continuation.finish(throwing: AgentSessionError.cancelled)
                        return
                    }

                    continuation.yield(.retrieved(chunks: chunks))

                    // 4. Compose prompt and stream from the LLM.
                    let (system, user) = composer.compose(
                        kind: .onDemand,
                        question: sanitized,
                        chunks: chunks
                    )

                    var accumulated = ""
                    let llmStream = llm.stream(
                        system: system,
                        userMessage: user,
                        model: nil,
                        temperature: 0.2,
                        maxTokens: 1200
                    )

                    for try await event in llmStream {
                        if Task.isCancelled {
                            continuation.finish(throwing: AgentSessionError.cancelled)
                            return
                        }
                        switch event {
                        case .textDelta(let delta):
                            accumulated += delta
                            continuation.yield(.textDelta(delta))
                        case .complete(let response):
                            if accumulated.isEmpty {
                                accumulated = response.text
                            }
                        }
                    }

                    // 5. Final event with the full text + the chunks that were cited.
                    continuation.yield(.complete(finalText: accumulated, citedChunks: chunks))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AgentSessionError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Input sanitization (Slice 2 minimum)

    /// Phase 3 moves this into `GuardrailGate.sanitizeUserInput`. For Slice 2
    /// we do the bare minimum to keep the pipeline clean: trim whitespace,
    /// cap length, strip ASCII control chars except newline.
    nonisolated static func sanitizeInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(4000))
        let cleaned = capped.unicodeScalars.filter { scalar in
            if scalar.value == 0x0A { return true }  // keep newlines
            return scalar.value >= 0x20  // drop control chars
        }
        return String(String.UnicodeScalarView(cleaned))
    }
}

/// One event in the lifecycle of an `AgentSession.ask(...)` call.
enum AgentEvent: Sendable {
    case started(question: String)
    case retrieving(sourceIDs: [String])
    case retrieved(chunks: [SourceChunk])
    case textDelta(String)
    case complete(finalText: String, citedChunks: [SourceChunk])
}

enum AgentSessionError: LocalizedError, Sendable {
    case emptyQuestion
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptyQuestion:
            return "Empty question. Type something and try again."
        case .cancelled:
            return "Query cancelled."
        }
    }
}
