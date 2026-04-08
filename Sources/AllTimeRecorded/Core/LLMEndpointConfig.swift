import Foundation

/// Runtime configuration for the LLM endpoint CatchMeUp talks to.
///
/// All fields are `UserDefaults`-backed and can be changed at runtime via
/// `defaults write AllTimeRecorded CatchMeUp.llm.<key> "<value>"`. This is
/// deliberate so that dev/relay/production endpoints can be swapped without
/// recompiling the app.
///
/// Secret material (the actual auth token) lives in Keychain via
/// `KeychainStore`, not here. This struct holds only non-sensitive config.
///
/// Supported deployment shapes:
///   1. **Direct Anthropic** — default. baseURL = https://api.anthropic.com, format = anthropic.
///      Token is a `sk-ant-...` API key.
///   2. **Claude Code-compatible relay** — e.g. `code.milus.one/api`. baseURL points
///      at the relay, format = anthropic. Token is a relay-provided `cr_...` string.
///   3. **OpenAI / OpenAI-compatible** — e.g. LM Studio, Ollama, OpenRouter. baseURL
///      points at the OpenAI endpoint, format = openai. Token is whatever the
///      provider's auth scheme is.
///
/// Phase 2's `AnthropicClient` reads this config at construction time.
enum LLMEndpointConfig {
    private static let baseURLKey     = "CatchMeUp.llm.baseURL"
    private static let apiFormatKey   = "CatchMeUp.llm.apiFormat"
    private static let defaultModelKey = "CatchMeUp.llm.defaultModel"

    /// Wire format of the endpoint. Determines request body shape, path,
    /// header style, and response parsing in Phase 2's `AnthropicClient`.
    enum APIFormat: String, CaseIterable, Sendable {
        /// Anthropic Messages API.
        /// - Path: `POST /v1/messages`
        /// - Auth: `x-api-key: <token>` header
        /// - Request body: Anthropic's `{model, messages, system, max_tokens, ...}` shape
        /// - Response: Anthropic content-block stream (`event: content_block_delta`)
        /// - Relays like `code.milus.one/api` typically speak this format.
        case anthropic

        /// OpenAI Chat Completions API.
        /// - Path: `POST /v1/chat/completions`
        /// - Auth: `Authorization: Bearer <token>` header
        /// - Request body: OpenAI's `{model, messages, temperature, ...}` shape
        /// - Response: OpenAI choice stream (`data: {...}`)
        /// - Used by OpenAI direct, LM Studio, Ollama, OpenRouter, Azure, etc.
        case openai
    }

    /// Current base URL. Defaults to direct Anthropic if unset.
    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: baseURLKey),
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://api.anthropic.com")!
    }

    static func setBaseURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: baseURLKey)
    }

    /// Current API format. Defaults to Anthropic.
    static var apiFormat: APIFormat {
        if let raw = UserDefaults.standard.string(forKey: apiFormatKey),
           let format = APIFormat(rawValue: raw) {
            return format
        }
        return .anthropic
    }

    static func setAPIFormat(_ format: APIFormat) {
        UserDefaults.standard.set(format.rawValue, forKey: apiFormatKey)
    }

    /// Default model identifier used when a call site doesn't specify one.
    /// Plan commits to `claude-opus-4-6` (Claude Opus 4.6, see `docs/PLAN.md` §2 D3).
    static var defaultModel: String {
        UserDefaults.standard.string(forKey: defaultModelKey) ?? "claude-opus-4-6"
    }

    static func setDefaultModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: defaultModelKey)
    }

    /// A single immutable snapshot of the config, suitable for passing into
    /// an `AnthropicClient` at construction time. Phase 2 uses this.
    struct Snapshot: Sendable {
        let baseURL: URL
        let apiFormat: APIFormat
        let defaultModel: String
    }

    static func snapshot() -> Snapshot {
        Snapshot(
            baseURL: baseURL,
            apiFormat: apiFormat,
            defaultModel: defaultModel
        )
    }
}
