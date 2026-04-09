import Foundation

/// Data source backed by LEANN's transcripts index. Built by
/// `TranscriptIndexer` from Whisper output.
///
/// Falls back gracefully: if `transcripts_index` doesn't exist yet
/// (no audio has been transcribed), `query` returns an empty array
/// rather than throwing.
struct TranscriptDataSource: DataSource {
    let id = "transcripts"
    let displayName = "Audio Transcripts"
    let requiresConsent = false  // user's own audio — no consent needed

    let bridge: any LEANNBridging
    let indexName: String

    init(bridge: any LEANNBridging, indexName: String = "transcripts_index") {
        self.bridge = bridge
        self.indexName = indexName
    }

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        do {
            return try await bridge.search(index: indexName, query: question, topK: topK)
        } catch {
            // Index may not exist yet — this is fine, just return empty.
            let desc = String(describing: error)
            if desc.contains("not found") || desc.contains("No such") || desc.contains("does not exist") {
                return []
            }
            throw error
        }
    }
}
