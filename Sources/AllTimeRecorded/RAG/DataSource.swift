import Foundation

/// A chunk of retrieved content from any `DataSource`. This is the universal
/// currency of CatchMeUp's retrieval layer: LEANN returns these, CrossRefEngine
/// dedupes and reranks these, PromptComposer wraps these in `<source>` tags.
struct SourceChunk: Sendable, Hashable, Codable, Identifiable {
    /// Unique identifier. Convention: `"<sourceID>#<local-id>"`,
    /// e.g. `"mail#msg-12345-chunk-3"` or `"transcripts#2026-04-08T14:32:00"`.
    let id: String

    /// Source system identifier: `"mail"`, `"wechat"`, `"transcripts"`, `"files"`, `"calendar"`.
    let sourceID: String

    /// Short human-readable label. For mail: subject. For chat: group name or sender.
    /// For transcripts: `YYYY-MM-DD HH:MM`. For files: basename.
    let title: String

    /// Raw retrieved text. UNSANITIZED by `LEANNBridge`; sanitization happens
    /// in `GuardrailGate.scrubChunk` during `CrossRefEngine.gather`.
    let body: String

    /// When the content was originally created, if available.
    let timestamp: Date?

    /// Canonical pointer the UI can click to "jump to source".
    /// Examples: `mailto:...`, `file:///.../path.pdf`, `catchmeup://transcript/2026-04-08#14:32`.
    let originURI: String?

    /// LEANN's own relevance score for this chunk. Higher is more relevant.
    let score: Double
}

/// A single indexed source CatchMeUp can query. All the actual retrieval work
/// ultimately flows through LEANN; `DataSource` conformers are thin adapters
/// that encode "which index", "what display name", and "do we need consent".
protocol DataSource: Sendable {
    /// Machine id used in chunk IDs and audit logs. Must be stable across runs.
    var id: String { get }

    /// Human-readable label shown in Settings and consent prompts.
    var displayName: String { get }

    /// Whether `ConsentLedger` should gate queries to this source behind a
    /// first-use consent prompt. Transcripts (user's own audio) don't need
    /// this; mail/wechat/files do.
    var requiresConsent: Bool { get }

    /// Run a retrieval query and return up to `topK` chunks.
    func query(question: String, topK: Int) async throws -> [SourceChunk]
}
