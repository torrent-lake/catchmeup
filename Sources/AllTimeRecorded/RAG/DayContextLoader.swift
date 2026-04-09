import Combine
import Foundation

/// Async loader that fetches LEANN chunks for a given day and publishes
/// them for the heatmap and word cloud. Called when the user switches days.
@MainActor
final class DayContextLoader: ObservableObject {
    @Published var emailChunks: [SourceChunk] = []
    @Published var chatChunks: [SourceChunk] = []
    @Published var fileChunks: [SourceChunk] = []
    @Published var transcriptChunks: [SourceChunk] = []
    @Published var isLoading = false

    /// AI-generated word cloud keywords for the current day.
    /// Each entry: (keyword, weight 0-1, source color hint).
    @Published var aiKeywords: [(word: String, weight: Double, color: String)] = []
    @Published var aiKeywordsLoading = false

    private let sources: [any DataSource]
    private let llm: (any LLMClient)?
    private var currentTask: Task<Void, Never>?
    private var keywordTask: Task<Void, Never>?
    private var keywordCache: [String: [(word: String, weight: Double, color: String)]] = [:]

    init(sources: [any DataSource], llm: (any LLMClient)? = nil) {
        self.sources = sources
        self.llm = llm
    }

    /// Load context for a given day. Queries each LEANN source with a
    /// time-scoped question and collects results.
    func loadDay(_ day: Date) {
        currentTask?.cancel()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dayStr = df.string(from: day)

        isLoading = true

        currentTask = Task { [weak self] in
            guard let self else { return }

            // Query each source with broad terms (LEANN semantic search
            // doesn't handle date-based queries well, so we use topic-based queries)
            async let mailResult = self.querySource(ids: ["mail"], query: "Cornell assignment deadline class email")
            async let chatResult = self.querySource(ids: ["wechat", "imessage"], query: "homework project meeting chat")
            async let fileResult = self.querySource(ids: ["files", "transcripts"], query: "lecture notes document file")
            async let reminderResult = self.querySource(ids: ["reminders"], query: "todo reminder task")

            let mail = await mailResult
            let chat = await chatResult
            let files = await fileResult
            _ = await reminderResult

            if !Task.isCancelled {
                await MainActor.run {
                    self.emailChunks = mail
                    self.chatChunks = chat
                    self.fileChunks = files
                    self.transcriptChunks = []
                    self.isLoading = false
                }
            }
        }
    }

    /// Generate AI-powered word cloud keywords for a day.
    func generateAIKeywords(for day: Date, calendarEvents: [CalendarOverlayEvent], transcriptPath: URL?) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dayKey = df.string(from: day)

        guard let llm else {
            // No LLM configured — fall back to empty
            aiKeywords = []
            return
        }

        keywordTask?.cancel()
        aiKeywords = []
        aiKeywordsLoading = true

        keywordTask = Task { [weak self] in
            guard let self else { return }

            // Build context summary for the AI
            var context = "Date: \(dayKey)\n\n"

            // Calendar events
            if !calendarEvents.isEmpty {
                context += "Calendar events today:\n"
                let dateFmt = DateFormatter()
                dateFmt.dateFormat = "HH:mm"
                for event in calendarEvents.prefix(15) {
                    context += "- \(dateFmt.string(from: event.startAt)) \(event.title)"
                    if let loc = event.location, !loc.isEmpty { context += " @ \(loc)" }
                    context += "\n"
                }
                context += "\n"
            }

            // Transcript excerpt
            if let path = transcriptPath,
               let text = try? String(contentsOf: path, encoding: .utf8) {
                // Take ~2000 chars from the middle (skip start/end noise)
                let lines = text.split(separator: "\n").filter { $0.count > 20 }.map(String.init)
                let sampleStr = Array(lines.prefix(40)).joined(separator: "\n")
                if !sampleStr.isEmpty {
                    context += "Audio transcript excerpts:\n\(String(sampleStr.prefix(2000)))\n\n"
                }
            }

            // LEANN chunks
            let allChunks = await MainActor.run {
                self.emailChunks + self.chatChunks
            }
            if !allChunks.isEmpty {
                context += "Email/chat excerpts:\n"
                for chunk in allChunks.prefix(5) {
                    context += "- \(String(chunk.body.prefix(200)))\n"
                }
            }

            guard !Task.isCancelled else { return }

            // Ask Claude to extract keywords
            let system = """
            Extract 12-15 meaningful topic keywords from this person's day context. \
            Return ONLY a comma-separated list of keywords, nothing else. \
            Each keyword should be 1-3 words. Focus on: meetings, projects, people, \
            courses, deadlines, key decisions. Skip generic words like "meeting" or "email". \
            Prefer specific names, topics, and action items.
            """

            do {
                let response = try await llm.complete(
                    system: system,
                    userMessage: context,
                    model: nil,
                    temperature: 0.3,
                    maxTokens: 200
                )

                let keywords = response.text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count < 30 }

                // Assign weights (first keywords = more important) and colors
                let colors = ["calendar", "cyan", "violet", "green", "pink", "blue"]
                let result: [(String, Double, String)] = keywords.enumerated().map { i, kw in
                    let weight = 1.0 - Double(i) / Double(max(keywords.count, 1)) * 0.6
                    let color = colors[i % colors.count]
                    return (kw, weight, color)
                }

                await MainActor.run {
                    self.aiKeywords = result
                    self.aiKeywordsLoading = false
                    self.keywordCache[dayKey] = result
                }
            } catch {
                await MainActor.run {
                    self.aiKeywordsLoading = false
                }
            }
        }
    }

    private func querySource(ids: [String], query: String) async -> [SourceChunk] {
        let idSet = Set(ids)
        let matching = sources.filter { idSet.contains($0.id) }
        var results: [SourceChunk] = []
        for source in matching {
            do {
                let chunks = try await source.query(question: query, topK: 10)
                results.append(contentsOf: chunks)
            } catch {
                // Silent failure — source might not be available
            }
        }
        return results
    }
}
