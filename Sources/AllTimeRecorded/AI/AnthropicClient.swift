import Foundation

/// `LLMClient` implementation that talks to the Anthropic Messages API
/// (either directly at `api.anthropic.com` or via a Claude Code-compatible
/// relay such as `code.milus.one/api`).
///
/// Reads config at construction time from `LLMEndpointConfig.snapshot()` and
/// the auth token from `KeychainStore.readLLMAuthToken()`. Honors the
/// `apiFormat` setting but currently only implements the `.anthropic` path;
/// the `.openai` path throws an explicit "not implemented" error so mis-
/// configuration surfaces loudly rather than silently failing.
///
/// Auth strategy: sends BOTH `x-api-key` and `Authorization: Bearer` headers
/// in the same request. Anthropic's own API documents that either works;
/// most relays accept at least one. Sending both is safe and maximally
/// compatible, which matters because we can't know every relay's quirks.
actor AnthropicClient: LLMClient {
    private let session: URLSession
    private let config: LLMEndpointConfig.Snapshot

    /// - Parameter config: the snapshot at construction time. A new
    ///   `AnthropicClient` is cheap to construct, so re-instantiate when
    ///   config changes rather than mutating in place.
    init(config: LLMEndpointConfig.Snapshot = LLMEndpointConfig.snapshot(),
         session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - LLMClient conformance

    func complete(
        system: String,
        userMessage: String,
        model: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> LLMResponse {
        let stream = stream(
            system: system,
            userMessage: userMessage,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        for try await event in stream {
            if case .complete(let response) = event {
                return response
            }
        }
        throw LLMClientError.emptyResponse
    }

    nonisolated func stream(
        system: String,
        userMessage: String,
        model: String?,
        temperature: Double,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(
                        system: system,
                        userMessage: userMessage,
                        model: model ?? config.defaultModel,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )

                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        // Drain the body into a string so the error message is useful.
                        var bodyBytes = Data()
                        for try await byte in bytes {
                            bodyBytes.append(byte)
                            if bodyBytes.count > 10_000 { break }  // cap
                        }
                        let bodyString = String(data: bodyBytes, encoding: .utf8) ?? "<non-utf8 body>"
                        throw LLMClientError.httpStatus(code: http.statusCode, body: bodyString)
                    }

                    let decoderStream = AnthropicStreamingDecoder.decode(lines: bytes.lines)
                    for try await event in decoderStream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMClientError.cancelled)
                } catch let err as LLMClientError {
                    continuation.finish(throwing: err)
                } catch let err as URLError {
                    continuation.finish(throwing: LLMClientError.transport(underlying: err.localizedDescription))
                } catch {
                    continuation.finish(throwing: LLMClientError.transport(underlying: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request construction

    nonisolated private func buildRequest(
        system: String,
        userMessage: String,
        model: String,
        temperature: Double,
        maxTokens: Int
    ) throws -> URLRequest {
        switch config.apiFormat {
        case .anthropic:
            return try buildAnthropicRequest(
                system: system,
                userMessage: userMessage,
                model: model,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .openai:
            // Slice 1 scope: anthropic only. The protocol enum lets us ship
            // this in a later slice without breaking callers.
            throw LLMClientError.decodeFailed("OpenAI API format is not yet implemented. Switch apiFormat back to 'anthropic' via `defaults write AllTimeRecorded CatchMeUp.llm.apiFormat anthropic`.")
        }
    }

    nonisolated private func buildAnthropicRequest(
        system: String,
        userMessage: String,
        model: String,
        temperature: Double,
        maxTokens: Int
    ) throws -> URLRequest {
        guard let token = KeychainStore.readLLMAuthToken(), !token.isEmpty else {
            throw LLMClientError.missingAuthToken
        }

        let endpoint = config.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("messages")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        // Send BOTH auth headers for maximum relay compatibility. Anthropic
        // direct accepts either; relays vary.
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.setValue("CatchMeUp/0.1 (macOS)", forHTTPHeaderField: "user-agent")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
            "system": system,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage,
                ]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        return request
    }
}
