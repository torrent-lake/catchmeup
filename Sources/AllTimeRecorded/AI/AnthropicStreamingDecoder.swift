import Foundation

/// Decodes Anthropic's Messages API Server-Sent Events stream into
/// `LLMStreamEvent` values. Parses line-by-line from an `AsyncLineSequence`.
///
/// The Anthropic event protocol (as of 2024/2025 versions) looks like:
/// ```
/// event: message_start
/// data: {"type":"message_start","message":{"id":"...","model":"...","usage":{...}}}
///
/// event: content_block_start
/// data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
///
/// event: content_block_delta
/// data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
///
/// event: content_block_delta
/// data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", "}}
///
/// event: content_block_stop
/// data: {"type":"content_block_stop","index":0}
///
/// event: message_delta
/// data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":15}}
///
/// event: message_stop
/// data: {"type":"message_stop"}
/// ```
///
/// We accumulate text deltas from `content_block_delta` → `text_delta`,
/// track usage from `message_delta.usage`, track model from `message_start.message.model`,
/// and emit a final `.complete(LLMResponse)` at `message_stop`.
///
/// Unknown event types and unparseable data lines are ignored (forward-compat
/// posture for future Anthropic events like tool_use, thinking blocks, etc.).
struct AnthropicStreamingDecoder {

    /// Parse an async sequence of UTF-8 lines from an SSE stream and yield
    /// `LLMStreamEvent`s. The caller is responsible for providing a byte
    /// stream already decoded into lines (e.g., `URLSession.bytes(for:).lines`).
    static func decode<Lines: AsyncSequence & Sendable>(
        lines: Lines
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> where Lines.Element == String, Lines.AsyncIterator: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                var accumulatedText = ""
                var inputTokens: Int?
                var outputTokens: Int?
                var stopReason: String?
                var modelReported: String?
                var pendingEventName: String?
                var pendingDataLines: [String] = []
                var linesSeen = 0
                var eventsDispatched = 0
                var completionYielded = false

                let debugEnabled = ProcessInfo.processInfo.environment["CMU_DEBUG_SSE"] == "1"
                func debug(_ message: @autoclosure () -> String) {
                    if debugEnabled {
                        FileHandle.standardError.write(Data("[SSE] \(message())\n".utf8))
                    }
                }

                func dispatchPendingEvent() {
                    defer {
                        pendingEventName = nil
                        pendingDataLines.removeAll(keepingCapacity: true)
                    }
                    guard !pendingDataLines.isEmpty else { return }
                    let dataString = pendingDataLines.joined()
                    // Ignore the sentinel `[DONE]` that some servers send.
                    if dataString == "[DONE]" { return }
                    guard let jsonData = dataString.data(using: .utf8) else { return }

                    do {
                        let anyJSON = try JSONSerialization.jsonObject(with: jsonData)
                        guard let obj = anyJSON as? [String: Any] else { return }
                        let type = obj["type"] as? String ?? pendingEventName ?? ""
                        eventsDispatched += 1
                        debug("dispatch type=\(type) (#\(eventsDispatched)) data=\(dataString.prefix(120))")

                        switch type {
                        case "message_start":
                            if let message = obj["message"] as? [String: Any] {
                                modelReported = message["model"] as? String
                                if let usage = message["usage"] as? [String: Any] {
                                    inputTokens = usage["input_tokens"] as? Int
                                }
                            }

                        case "content_block_delta":
                            if let delta = obj["delta"] as? [String: Any],
                               let deltaType = delta["type"] as? String {
                                switch deltaType {
                                case "text_delta":
                                    if let text = delta["text"] as? String, !text.isEmpty {
                                        accumulatedText += text
                                        continuation.yield(.textDelta(text))
                                    }
                                case "thinking_delta":
                                    // Anthropic's extended-thinking content blocks.
                                    // We don't surface these to the user UI yet, but
                                    // they do count toward latency. Ignored for now.
                                    break
                                default:
                                    // Future block types: tool_use_delta, input_json_delta, etc.
                                    break
                                }
                            }

                        case "message_delta":
                            if let delta = obj["delta"] as? [String: Any] {
                                if let sr = delta["stop_reason"] as? String {
                                    stopReason = sr
                                }
                            }
                            if let usage = obj["usage"] as? [String: Any] {
                                if let out = usage["output_tokens"] as? Int {
                                    outputTokens = out
                                }
                                // Some relays report input_tokens here too.
                                if let inp = usage["input_tokens"] as? Int, inputTokens == nil {
                                    inputTokens = inp
                                }
                            }

                        case "message_stop":
                            let response = LLMResponse(
                                text: accumulatedText,
                                inputTokens: inputTokens,
                                outputTokens: outputTokens,
                                stopReason: stopReason,
                                modelReported: modelReported
                            )
                            continuation.yield(.complete(response))
                            completionYielded = true

                        case "error":
                            if let err = obj["error"] as? [String: Any],
                               let message = err["message"] as? String {
                                continuation.finish(throwing: LLMClientError.decodeFailed("Anthropic error: \(message)"))
                                return
                            }

                        case "ping":
                            // keep-alive, ignore
                            break

                        default:
                            // Unknown event type — forward-compat, ignore.
                            break
                        }
                    } catch {
                        // Malformed JSON in a data line — skip this event, keep stream alive.
                    }
                }

                do {
                    for try await rawLine in lines {
                        linesSeen += 1
                        if Task.isCancelled {
                            throw LLMClientError.cancelled
                        }
                        let line = rawLine.trimmingCharacters(in: .whitespaces)
                        debug("line#\(linesSeen) raw=\(rawLine.prefix(120))")
                        if line.isEmpty {
                            // Empty line is the canonical SSE event separator,
                            // but Swift's AsyncLineSequence sometimes collapses
                            // these. We dispatch here as a fast path; the
                            // `event:`-header fallback below covers the
                            // AsyncLineSequence-collapsing case.
                            dispatchPendingEvent()
                            continue
                        }
                        if line.hasPrefix(":") {
                            // SSE comment line, ignore.
                            continue
                        }
                        if let colon = line.firstIndex(of: ":") {
                            let field = String(line[..<colon])
                            var value = String(line[line.index(after: colon)...])
                            if value.hasPrefix(" ") {
                                value.removeFirst()
                            }
                            switch field {
                            case "event":
                                // If we already have pending data buffered from
                                // the previous event, dispatch it NOW. This is
                                // the critical workaround for AsyncLineSequence
                                // collapsing the empty separator lines on macOS:
                                // the start of a new `event:` header also marks
                                // the end of the previous event.
                                if !pendingDataLines.isEmpty {
                                    dispatchPendingEvent()
                                }
                                pendingEventName = value
                            case "data":
                                pendingDataLines.append(value)
                            case "id", "retry":
                                // Ignored fields per SSE spec.
                                break
                            default:
                                // Unknown field, ignore.
                                break
                            }
                        }
                    }
                    // Stream ended. Dispatch anything still pending.
                    dispatchPendingEvent()
                    debug("stream ended lines=\(linesSeen) events=\(eventsDispatched) accumulated=\(accumulatedText.count) chars")

                    // Some relays don't emit a proper `message_stop`. If we
                    // never got one but we did accumulate text, synthesize a
                    // completion event so the caller isn't left hanging.
                    if !completionYielded && !accumulatedText.isEmpty {
                        let response = LLMResponse(
                            text: accumulatedText,
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            stopReason: stopReason ?? "end_of_stream",
                            modelReported: modelReported
                        )
                        continuation.yield(.complete(response))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMClientError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
