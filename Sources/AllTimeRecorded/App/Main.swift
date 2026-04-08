import AppKit
import Foundation

@main
enum AllTimeRecordedMain {
    static func main() {
        // Dev-only CLI probes. These bypass NSApplication entirely and run
        // a specific subsystem check to stdout, then exit. Useful for shell-
        // driven debug without needing to click status bar menu items.
        //
        // Usage:
        //   .build/debug/AllTimeRecorded --probe-claude
        //   CMU_DEBUG_SSE=1 .build/debug/AllTimeRecorded --probe-claude  (verbose SSE parse log on stderr)
        if CommandLine.arguments.contains("--probe-claude") {
            runClaudeCLIProbe()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static func runClaudeCLIProbe() {
        let sema = DispatchSemaphore(value: 0)
        Task {
            defer { sema.signal() }

            let config = LLMEndpointConfig.snapshot()
            print("[probe] baseURL = \(config.baseURL.absoluteString)")
            print("[probe] apiFormat = \(config.apiFormat.rawValue)")
            print("[probe] defaultModel = \(config.defaultModel)")

            guard let token = KeychainStore.readLLMAuthToken(), !token.isEmpty else {
                print("[probe] FAIL: no auth token in Keychain or env")
                exit(1)
            }
            let maskedLen = token.count
            print("[probe] token found (length \(maskedLen), masked)")

            let client = AnthropicClient(config: config)
            let composer = PromptComposer()
            let (system, user) = composer.compose(kind: .debugProbe, question: "ping", chunks: [])
            print("[probe] system prompt = \(system)")
            print("[probe] user message = \(user)")

            print("[probe] starting stream…")
            do {
                let stream = client.stream(
                    system: system,
                    userMessage: user,
                    model: nil,
                    temperature: 0.0,
                    maxTokens: 20
                )
                var eventCount = 0
                var finalText = ""
                for try await event in stream {
                    eventCount += 1
                    switch event {
                    case .textDelta(let delta):
                        print("[probe] event #\(eventCount) .textDelta = \(delta.debugDescription)")
                    case .complete(let response):
                        print("[probe] event #\(eventCount) .complete")
                        finalText = response.text
                        print("[probe]   text = \(response.text.debugDescription)")
                        print("[probe]   model = \(response.modelReported ?? "—")")
                        print("[probe]   inputTokens = \(response.inputTokens.map(String.init) ?? "—")")
                        print("[probe]   outputTokens = \(response.outputTokens.map(String.init) ?? "—")")
                        print("[probe]   stopReason = \(response.stopReason ?? "—")")
                    }
                }
                print("[probe] stream ended after \(eventCount) events")
                if eventCount == 0 {
                    print("[probe] FAIL: stream produced zero events")
                    exit(2)
                }
                if finalText.isEmpty {
                    print("[probe] FAIL: no text in completion")
                    exit(3)
                }
                print("[probe] OK")
                exit(0)
            } catch {
                print("[probe] FAIL: \(error)")
                exit(4)
            }
        }
        sema.wait()
    }
}
