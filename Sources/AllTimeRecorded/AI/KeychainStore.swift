import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing the user's LLM auth token.
///
/// CatchMeUp supports three deployment shapes (see `LLMEndpointConfig`):
///   1. Direct Anthropic API (token is `sk-ant-...`)
///   2. Claude Code-compatible relay (token is `cr_...` or similar)
///   3. OpenAI-compatible endpoint (token is `sk-...` or provider-specific)
///
/// All three live in the same Keychain slot under service
/// `"com.catchmeup.anthropic"` account `"default"`. Only one token is active
/// at a time; if the user changes endpoints, they store a new token.
///
/// Design goals:
/// - Never writes the token to disk outside the Keychain.
/// - Uses `kSecAttrAccessibleAfterFirstUnlock` so the token survives reboots
///   but still requires the user to unlock their Mac at least once after boot.
/// - Stable service/account strings so external tooling (and the user's own
///   `security add-generic-password` invocation) can target the same slot.
/// - Dev fallback: if Keychain has no entry, `readLLMAuthToken()` returns the
///   value of the `ANTHROPIC_AUTH_TOKEN` environment variable (Claude Code /
///   relay convention) OR `ANTHROPIC_API_KEY` (direct Anthropic convention).
///   This is for local dev convenience only — production onboarding writes
///   into Keychain.
///
/// Used by: `AnthropicClient` in Phase 2 (direct reads), and `LEANNBridge`
/// when it needs to set `ANTHROPIC_API_KEY` before spawning a `leann ask`
/// subprocess.
enum KeychainStore {
    static let service = "com.catchmeup.anthropic"
    static let account = "default"

    enum Failure: LocalizedError {
        case unexpectedStatus(OSStatus)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain operation failed with OSStatus \(status)."
            case .encodingFailed:
                return "Could not encode the LLM auth token as UTF-8."
            }
        }
    }

    /// Store or replace the LLM auth token in the Keychain.
    /// Works for any of: Anthropic API key, Claude Code relay token, OpenAI key.
    static func storeLLMAuthToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw Failure.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Try update first; if the item doesn't exist, add it.
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Failure.unexpectedStatus(addStatus)
            }
            return
        }
        throw Failure.unexpectedStatus(updateStatus)
    }

    /// Read the stored LLM auth token, or `nil` if none is set.
    /// Falls back to `ANTHROPIC_AUTH_TOKEN` (relay) then `ANTHROPIC_API_KEY`
    /// (direct Anthropic) env vars for dev convenience.
    static func readLLMAuthToken() -> String? {
        // 1. Keychain — the canonical storage location.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8)
        {
            return token
        }

        // 2. Dev fallback: relay-style env var (ANTHROPIC_AUTH_TOKEN is what
        //    Claude Code CLI uses when configured against a relay).
        if let token = ProcessInfo.processInfo.environment["ANTHROPIC_AUTH_TOKEN"],
           !token.isEmpty
        {
            return token
        }

        // 3. Dev fallback: direct-Anthropic env var (ANTHROPIC_API_KEY is the
        //    Anthropic SDK default).
        if let token = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !token.isEmpty
        {
            return token
        }

        return nil
    }

    /// Remove the stored token. Used by Settings → Keys → "Sign out".
    static func deleteLLMAuthToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw Failure.unexpectedStatus(status)
        }
    }
}
