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
    private let guardrail: GuardrailGate
    private let defaultSources: [any DataSource]

    init(
        llm: any LLMClient,
        crossRef: CrossRefEngine,
        composer: PromptComposer = PromptComposer(),
        guardrail: GuardrailGate = GuardrailGate(),
        defaultSources: [any DataSource]
    ) {
        self.llm = llm
        self.crossRef = crossRef
        self.composer = composer
        self.guardrail = guardrail
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

                    // 1. Sanitize user input via GuardrailGate.
                    let guardrail = await self.guardrail
                    let sanitizedInput = guardrail.sanitizeUserInput(question)
                    let sanitized = sanitizedInput.text
                    guard !sanitized.isEmpty else {
                        continuation.finish(throwing: AgentSessionError.emptyQuestion)
                        return
                    }

                    continuation.yield(.started(question: sanitized))

                    // 2. Announce retrieval target.
                    let sourceIDs = sources.map(\.id)
                    continuation.yield(.retrieving(sourceIDs: sourceIDs))

                    // 3. Retrieve via CrossRefEngine.
                    let rawChunks = await crossRef.gather(
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

                    // 3.5. Scrub chunks through guardrail (removes injection payloads).
                    let chunks = rawChunks.map { guardrail.scrubChunk($0) }

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

                    // 5. Validate and sanitize output.
                    let validation = guardrail.validateOutput(accumulated, chunks: chunks)
                    let finalOutput = validation.sanitizedText

                    // 6. Final event with the full text + the chunks that were cited.
                    continuation.yield(.complete(finalText: finalOutput, citedChunks: chunks))
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

    // Input sanitization is now handled by GuardrailGate.
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
