import Foundation

/// Data source backed by LEANN's `mail_index`. The user already has this
/// index built on their machine (26 MB as of plan time). We just wrap it.
///
/// See `docs/LEANN_INTEGRATION.md` §3 for existing-indices status.
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
