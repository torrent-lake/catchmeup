import Foundation

/// Assembles the final `(system, user)` message pair that gets sent to the LLM.
///
/// Responsibilities:
/// - Wrap every retrieved chunk in a numbered `<source>` tag with metadata.
/// - Wrap the user's question in `<user_content>` tags.
/// - Concatenate the wrapped pieces into a single user message body.
/// - Return the system prompt unmodified (it comes from `PromptTemplates`).
///
/// PromptComposer is the ONLY place that constructs the message body that
/// reaches `LLMClient`. Call sites do not hand-concatenate. This centralizes
/// the injection-defense wrapping and makes it impossible to accidentally ship
/// unsanitized content to the LLM.
///
/// See `docs/PROMPT_LIBRARY.md` §2 for the structural conventions and
/// `docs/SECURITY_THREATS.md` §2.1 for the threat model being defended against.
struct PromptComposer: Sendable {
    /// The kind of message we're composing. Currently only `.onDemand` is wired
    /// in Phase 2 Slice 2; pre-meeting brief and daily digest come in later slices.
    enum Kind: Sendable {
        case onDemand
        case debugProbe
    }

    /// Build the system + user pair.
    ///
    /// - Parameters:
    ///   - kind: which prompt template family to use.
    ///   - question: the user's raw question text. Will be wrapped in
    ///     `<user_content>` tags — the caller should have already run it
    ///     through `GuardrailGate.sanitizeUserInput` (Phase 3+).
    ///   - chunks: retrieved source chunks, ordered by rerank score. The
    ///     composer assigns 1-based IDs (`1`, `2`, `3`, ...) that match the
    ///     `[N]` citation format the model is instructed to use.
    /// - Returns: a pair of strings, `system` and `user`, ready to pass to
    ///   `LLMClient.stream(system:userMessage:...)`.
    func compose(
        kind: Kind,
        question: String,
        chunks: [SourceChunk]
    ) -> (system: String, user: String) {
        let system: String
        switch kind {
        case .onDemand:
            system = PromptTemplates.systemOnDemandAnswerV1
        case .debugProbe:
            system = PromptTemplates.debugProbeSystemV1
        }

        if kind == .debugProbe {
            // No chunks, no user wrapping — debug probe is a trivial ping.
            return (system, "ping")
        }

        var body = ""
        body += "<user_content>\n"
        body += question
        body += "\n</user_content>\n\n"

        if chunks.isEmpty {
            body += "(no sources retrieved)\n"
        } else {
            for (index, chunk) in chunks.enumerated() {
                body += Self.renderSourceTag(chunk: chunk, displayID: index + 1)
                body += "\n"
            }
        }

        body += "\nAnswer:"
        return (system, body)
    }

    /// Render a single `<source>` tag. Public for testing; callers should go
    /// through `compose(...)`.
    static func renderSourceTag(chunk: SourceChunk, displayID: Int) -> String {
        var attrs: [String] = []
        attrs.append("id=\"\(displayID)\"")
        attrs.append("type=\"\(escape(chunk.sourceID))\"")
        if let ts = chunk.timestamp {
            attrs.append("date=\"\(formatISO8601(ts))\"")
        }
        if let origin = chunk.originURI, !origin.isEmpty {
            attrs.append("origin=\"\(escape(origin))\"")
        }
        let attrString = attrs.joined(separator: " ")
        let safeBody = chunk.body
            .replacingOccurrences(of: "</source>", with: "&lt;/source&gt;")
        return "<source \(attrString)>\n\(safeBody)\n</source>"
    }

    /// Format a date as ISO 8601 for the `date` attribute on `<source>` tags.
    /// Builds a fresh formatter per call to keep the API Sendable-friendly
    /// under Swift 6 strict concurrency; source tag composition is not a hot
    /// path (happens once per query, not per token).
    private static func formatISO8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
