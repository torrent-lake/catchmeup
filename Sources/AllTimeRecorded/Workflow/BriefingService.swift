import Foundation

/// Generates pre-meeting briefs, daily digests, and proactive intelligence.
///
/// The service owns the full pipeline: retrieve → compose → stream → parse.
/// Results are cached to disk so repeated opens are instant.
actor BriefingService {
    private let llm: any LLMClient
    private let crossRef: CrossRefEngine
    private let composer: PromptComposer
    private let sources: [any DataSource]
    private let paths: AppPaths

    init(
        llm: any LLMClient,
        crossRef: CrossRefEngine,
        composer: PromptComposer = PromptComposer(),
        sources: [any DataSource],
        paths: AppPaths
    ) {
        self.llm = llm
        self.crossRef = crossRef
        self.composer = composer
        self.sources = sources
        self.paths = paths
    }

    // MARK: - Proactive: "What might I forget tomorrow?"

    /// Generate a proactive briefing for upcoming events, reminders, and
    /// pending items. This is the core "开启新的一天" demo scene.
    func generateProactiveBrief() async throws -> AsyncThrowingStream<AgentEvent, Error> {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        let dateStr = df.string(from: tomorrow)

        let question = """
        What are the important things I should not forget about for tomorrow (\(dateStr))? \
        Check my calendar events, reminders, recent emails, and any pending action items. \
        Highlight anything time-sensitive or easily forgotten.
        """

        return streamAnswer(question: question, kind: .proactive)
    }

    // MARK: - Pre-meeting brief

    func generatePreMeetingBrief(
        eventTitle: String,
        eventTime: Date,
        attendees: [String]
    ) async throws -> AsyncThrowingStream<AgentEvent, Error> {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let timeStr = df.string(from: eventTime)

        var question = """
        I have a meeting coming up: "\(eventTitle)" at \(timeStr).
        """
        if !attendees.isEmpty {
            question += " Attendees: \(attendees.joined(separator: ", "))."
        }
        question += """
         Find all relevant context from my email, chat history, files, and past meetings \
        related to this topic and these people. Summarize the key points I should know \
        before walking in.
        """

        return streamAnswer(question: question, kind: .preMeeting)
    }

    // MARK: - Daily digest

    func generateDailyDigest() async throws -> AsyncThrowingStream<AgentEvent, Error> {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        let today = df.string(from: Date())

        let question = """
        Give me an end-of-day summary for \(today). Include:
        1. Today's highlights — the 3-5 most important things that happened across my email, \
        calendar, chat, and files.
        2. Action items — commitments or tasks mentioned in today's communications.
        3. Things I may have missed — items from less-checked sources.
        4. Looking ahead — what's coming tomorrow and needs preparation.
        """

        return streamAnswer(question: question, kind: .dailyDigest)
    }

    // MARK: - File aggregation query

    /// Search for files related to a topic and return chunks with file paths.
    /// The UI layer uses the `originURI` from the returned chunks to build
    /// a draggable file collection.
    func gatherFiles(topic: String) async throws -> [SourceChunk] {
        let fileSources = sources.filter { $0.id == "files" }
        guard !fileSources.isEmpty else { return [] }

        return await crossRef.gather(
            question: topic,
            sources: fileSources,
            topKPerSource: 20,
            budgetChunks: 20,
            deadline: Date().addingTimeInterval(8)
        )
    }

    // MARK: - Internal

    private func streamAnswer(
        question: String,
        kind: Briefing.Kind
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let llm = self.llm
        let crossRef = self.crossRef
        let composer = self.composer
        let sources = self.sources

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started(question: question))

                    let sourceIDs = sources.map(\.id)
                    continuation.yield(.retrieving(sourceIDs: sourceIDs))

                    let chunks = await crossRef.gather(
                        question: question,
                        sources: sources,
                        topKPerSource: 5,
                        budgetChunks: 16,
                        deadline: Date().addingTimeInterval(12)
                    )

                    if Task.isCancelled { continuation.finish(); return }
                    continuation.yield(.retrieved(chunks: chunks))

                    let promptKind: PromptComposer.Kind
                    switch kind {
                    case .preMeeting: promptKind = .briefing
                    case .dailyDigest: promptKind = .dailyDigest
                    case .proactive: promptKind = .proactive
                    }

                    let (system, user) = composer.compose(
                        kind: promptKind,
                        question: question,
                        chunks: chunks
                    )

                    var accumulated = ""
                    let stream = llm.stream(
                        system: system,
                        userMessage: user,
                        model: nil,
                        temperature: 0.3,
                        maxTokens: 2000
                    )

                    for try await event in stream {
                        if Task.isCancelled { continuation.finish(); return }
                        switch event {
                        case .textDelta(let delta):
                            accumulated += delta
                            continuation.yield(.textDelta(delta))
                        case .complete(let response):
                            if accumulated.isEmpty { accumulated = response.text }
                        }
                    }

                    continuation.yield(.complete(finalText: accumulated, citedChunks: chunks))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
