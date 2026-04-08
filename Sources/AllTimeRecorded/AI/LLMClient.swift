import Foundation

/// Universal LLM client contract. CatchMeUp talks to Claude (direct Anthropic,
/// Claude Code-compatible relays, or any OpenAI-compatible endpoint) through
/// this single protocol. The concrete implementations read
/// `LLMEndpointConfig.snapshot()` and `KeychainStore.readLLMAuthToken()`
/// to decide which transport and auth to use.
///
/// Design notes:
/// - Every request is stateless. Multi-turn conversation state (if ever needed)
///   is the caller's responsibility — we keep the client simple.
/// - Streaming is the primary path. Non-streaming `complete(...)` is a
///   convenience that collects the stream and returns the final text.
/// - System prompts are a dedicated parameter, not embedded in messages,
///   because both Anthropic and OpenAI APIs treat them specially.
/// - Source chunks are already wrapped in `<source>` tags by `PromptComposer`
///   before the text reaches the client. The client does not know about
///   retrieval; it only knows about text-in / text-out.
protocol LLMClient: Sendable {
    /// One-shot non-streaming call. Returns the full answer when the stream ends.
    func complete(
        system: String,
        userMessage: String,
        model: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> LLMResponse

    /// Streaming call. Emits deltas as they arrive, then a `.complete` event
    /// when the stream ends. The stream throws on network/parse/auth errors.
    func stream(
        system: String,
        userMessage: String,
        model: String?,
        temperature: Double,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// Final response after a complete (or collected) LLM call.
struct LLMResponse: Sendable, Hashable {
    /// The full text of the assistant's answer.
    let text: String

    /// Input token count, when the API reports it.
    let inputTokens: Int?

    /// Output token count, when the API reports it.
    let outputTokens: Int?

    /// API-reported stop reason, e.g. "end_turn", "max_tokens", "stop_sequence".
    let stopReason: String?

    /// The model identifier the API actually served the response from.
    /// May differ from the requested model for relays that substitute.
    let modelReported: String?
}

/// Incremental events produced by `stream(...)`. The order is:
/// 1. Zero or more `.textDelta` events, in order, each carrying a new fragment.
/// 2. Exactly one `.complete` event, carrying the final response with usage.
enum LLMStreamEvent: Sendable {
    case textDelta(String)
    case complete(LLMResponse)
}

/// Errors surfaced by `LLMClient` implementations. The UI should translate
/// these into user-facing messages via `errorDescription`.
enum LLMClientError: LocalizedError, Sendable {
    case missingAuthToken
    case invalidBaseURL(String)
    case httpStatus(code: Int, body: String)
    case transport(underlying: String)
    case decodeFailed(String)
    case emptyResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAuthToken:
            return "No LLM auth token is configured. Add one via Settings → Keys (or Keychain slot com.catchmeup.anthropic/default)."
        case .invalidBaseURL(let url):
            return "LLM base URL is not a valid URL: \(url)"
        case .httpStatus(let code, let body):
            let snippet = String(body.prefix(300))
            return "LLM endpoint returned HTTP \(code). Response: \(snippet)"
        case .transport(let underlying):
            return "Network error talking to the LLM endpoint: \(underlying)"
        case .decodeFailed(let detail):
            return "Could not decode the LLM response: \(detail)"
        case .emptyResponse:
            return "The LLM returned no content."
        case .cancelled:
            return "LLM request was cancelled."
        }
    }
}
