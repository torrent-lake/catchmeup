import Foundation

/// Data source backed by LEANN's `mail_index`. Uses direct vector search
/// for reliability — the previous `leann ask` (LLM-powered RAG) path was
/// removed because it fails when the app uses a relay endpoint (the relay
/// auth token isn't compatible with LEANN's internal Anthropic client),
/// and its 30s timeout cascades into CrossRefEngine's 15s deadline, blocking
/// the fast `search` fallback from ever running.
struct MailDataSource: DataSource {
    let id = "mail"
    let displayName = "Apple Mail"
    let requiresConsent = true

    let bridge: any LEANNBridging
    let indexName: String

    init(bridge: any LEANNBridging, indexName: String = "mail_index") {
        self.bridge = bridge
        self.indexName = indexName
    }

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        try await bridge.search(index: indexName, query: question, topK: topK)
    }
}
