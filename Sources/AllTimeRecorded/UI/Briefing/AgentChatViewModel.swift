import Foundation
import SwiftUI

/// View model for the on-demand agent chat panel. Wraps an `AgentSession`
/// and publishes a single `state` property the UI binds to.
///
/// Phase 2 Slice 2 is **single-turn**: each submit replaces the previous
/// answer. Multi-turn history comes in Phase 3 (simple to add — track an
/// array of turns rather than a single state).
@MainActor
final class AgentChatViewModel: ObservableObject {
    /// The text the user is currently typing. Bound to the input field.
    @Published var inputText: String = ""

    /// The current state of the chat panel. The view renders based on this.
    @Published var state: ChatState = .idle

    /// The question the user submitted, retained for display while the
    /// answer is in-flight. Cleared when a new question is submitted.
    @Published private(set) var lastQuestion: String = ""

    enum ChatState: Equatable {
        /// No question in flight. Input field is empty, answer area shows a
        /// neutral prompt.
        case idle

        /// The session has accepted the question and is fanning out retrieval.
        /// The answer area shows a "Searching your…" status.
        case retrieving(sourceIDs: [String])

        /// Chunks came back and the LLM is streaming tokens. `text` grows as
        /// deltas arrive; `chunks` are the retrieved sources being cited.
        case streaming(text: String, chunks: [SourceChunk])

        /// Stream ended. Final text + the chunks that were in context.
        case complete(text: String, chunks: [SourceChunk])

        /// Something failed. The view shows the message as a soft warning
        /// and keeps the input field ready for another try.
        case error(message: String)
    }

    /// Whether the user has given feedback on the current answer.
    @Published var feedbackGiven: AuditEntry.Rating?

    /// File chunks available for drag-and-drop (populated by file aggregation queries).
    @Published var fileResults: [SourceChunk] = []

    private let session: AgentSession
    private let auditLog: AuditLog?
    private let briefingService: BriefingService?
    private var currentTask: Task<Void, Never>?

    init(
        session: AgentSession,
        auditLog: AuditLog? = nil,
        briefingService: BriefingService? = nil
    ) {
        self.session = session
        self.auditLog = auditLog
        self.briefingService = briefingService
    }

    /// Submit the current `inputText` as a new question. Cancels any
    /// in-flight query.
    func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentTask?.cancel()
        lastQuestion = trimmed
        inputText = ""
        feedbackGiven = nil
        fileResults = []
        state = .retrieving(sourceIDs: [])

        let stream = session.ask(question: trimmed)

        currentTask = Task { [weak self] in
            do {
                var accumulated = ""
                var chunks: [SourceChunk] = []
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .started:
                        await MainActor.run {
                            self?.state = .retrieving(sourceIDs: [])
                        }
                    case .retrieving(let sourceIDs):
                        await MainActor.run {
                            self?.state = .retrieving(sourceIDs: sourceIDs)
                        }
                    case .retrieved(let gathered):
                        chunks = gathered
                        await MainActor.run {
                            self?.state = .streaming(text: accumulated, chunks: chunks)
                        }
                    case .textDelta(let delta):
                        accumulated += delta
                        let currentChunks = chunks
                        let currentText = accumulated
                        await MainActor.run {
                            self?.state = .streaming(text: currentText, chunks: currentChunks)
                        }
                    case .complete(let finalText, let citedChunks):
                        let final = finalText
                        let cited = citedChunks
                        await MainActor.run {
                            self?.state = .complete(text: final, chunks: cited)
                        }
                    }
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                await MainActor.run {
                    self?.state = .error(message: message)
                }
            }
        }
    }

    /// Cancel the current in-flight query (if any) and reset to idle.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    /// Whether the UI should show the input field as disabled (in-flight).
    var isBusy: Bool {
        switch state {
        case .retrieving, .streaming:
            return true
        case .idle, .complete, .error:
            return false
        }
    }

    // MARK: - Feedback

    func giveFeedback(_ rating: AuditEntry.Rating) {
        feedbackGiven = rating
        guard let auditLog else { return }
        var hasher = Hasher()
        hasher.combine(lastQuestion)
        let hash = String(format: "%08x", abs(hasher.finalize()))
        Task {
            await auditLog.append(.feedbackEntry(
                questionHash: hash,
                rating: rating
            ))
        }
    }

    // MARK: - Proactive brief

    /// Ask "What might I forget tomorrow?"
    func askProactiveBrief() {
        guard let briefingService else { return }
        currentTask?.cancel()
        lastQuestion = "What should I not forget about tomorrow?"
        inputText = ""
        feedbackGiven = nil
        state = .retrieving(sourceIDs: [])

        currentTask = Task { [weak self] in
            do {
                let stream = try await briefingService.generateProactiveBrief()
                var accumulated = ""
                var chunks: [SourceChunk] = []
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .started:
                        await MainActor.run { self?.state = .retrieving(sourceIDs: []) }
                    case .retrieving(let sourceIDs):
                        await MainActor.run { self?.state = .retrieving(sourceIDs: sourceIDs) }
                    case .retrieved(let gathered):
                        chunks = gathered
                        await MainActor.run { self?.state = .streaming(text: accumulated, chunks: chunks) }
                    case .textDelta(let delta):
                        accumulated += delta
                        let t = accumulated; let c = chunks
                        await MainActor.run { self?.state = .streaming(text: t, chunks: c) }
                    case .complete(let text, let cited):
                        let t = text; let c = cited
                        await MainActor.run { self?.state = .complete(text: t, chunks: c) }
                    }
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                await MainActor.run { self?.state = .error(message: msg) }
            }
        }
    }

    // MARK: - File aggregation

    /// Gather files related to a topic. Returns chunks whose originURI
    /// points to local files. The UI can use these for drag-and-drop.
    func gatherFiles(topic: String) {
        guard let briefingService else { return }
        currentTask?.cancel()
        lastQuestion = "Gather files: \(topic)"
        state = .retrieving(sourceIDs: ["files"])

        currentTask = Task { [weak self] in
            do {
                let chunks = try await briefingService.gatherFiles(topic: topic)
                await MainActor.run {
                    self?.fileResults = chunks
                    self?.state = .complete(
                        text: "Found \(chunks.count) files related to \"\(topic)\". Drag the collection to upload.",
                        chunks: chunks
                    )
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                await MainActor.run { self?.state = .error(message: msg) }
            }
        }
    }
}
