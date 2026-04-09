import Foundation

/// Abstraction over LEANN CLI access. Exists so tests and previews can use a
/// mock bridge instead of spawning real subprocesses, and so Phase 4's
/// `LEANNDaemonClient` can drop in as a faster implementation without
/// changing any call sites.
///
/// See `docs/LEANN_INTEGRATION.md` for the CLI contract we depend on.
protocol LEANNBridging: Sendable {
    /// List available indices by name.
    func listIndices() async throws -> [String]

    /// Search a single index and return parsed chunks.
    func search(index: String, query: String, topK: Int) async throws -> [SourceChunk]

    /// Lower-level raw-stdout search — used by the Phase 1 dev UI that just
    /// wants to prove subprocess plumbing works. Returns whatever `leann search`
    /// printed to stdout (untouched, UTF-8 decoded).
    func searchRaw(index: String, query: String, topK: Int) async throws -> String

    /// Run `leann ask` with an LLM — returns the synthesized answer as a single chunk.
    /// Uses the configured API relay so LEANN's internal RAG produces a high-quality summary.
    func ask(index: String, query: String, topK: Int) async throws -> String
}
