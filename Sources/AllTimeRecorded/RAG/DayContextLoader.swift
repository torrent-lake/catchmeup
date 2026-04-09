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

    private let sources: [any DataSource]
    private var currentTask: Task<Void, Never>?

    init(sources: [any DataSource]) {
        self.sources = sources
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

            // Query each source type in parallel
            async let mailResult = querySource(id: "mail", query: "messages from \(dayStr)")
            async let chatResult = querySource(id: "wechat", query: "chat messages \(dayStr)")
            async let fileResult = querySource(id: "files", query: "files modified \(dayStr)")
            async let transcriptResult = querySource(id: "transcripts", query: "transcript \(dayStr)")

            let mail = await mailResult
            let chat = await chatResult
            let files = await fileResult
            let transcripts = await transcriptResult

            if !Task.isCancelled {
                await MainActor.run {
                    self.emailChunks = mail
                    self.chatChunks = chat
                    self.fileChunks = files
                    self.transcriptChunks = transcripts
                    self.isLoading = false
                }
            }
        }
    }

    private func querySource(id: String, query: String) async -> [SourceChunk] {
        let matching = sources.filter { $0.id == id || $0.id == "imessage" && id == "wechat" }
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
