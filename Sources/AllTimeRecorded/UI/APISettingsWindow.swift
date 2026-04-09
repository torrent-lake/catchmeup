import AppKit
import SwiftUI

/// A simple settings window for configuring the LLM endpoint URL and auth token.
/// Accessible from the status bar context menu.
@MainActor
final class APISettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = APISettingsView {
            self.window?.orderOut(nil)
            self.window = nil
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titlebarAppearsTransparent = true
        w.title = "API Settings"
        w.isMovableByWindowBackground = true
        w.center()
        w.contentViewController = NSHostingController(rootView: view)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

struct APISettingsView: View {
    let onDismiss: () -> Void

    @State private var baseURL: String = LLMEndpointConfig.baseURL.absoluteString
    @State private var token: String = KeychainStore.readLLMAuthToken() ?? ""
    @State private var model: String = LLMEndpointConfig.defaultModel
    @State private var format: LLMEndpointConfig.APIFormat = LLMEndpointConfig.apiFormat
    @State private var statusMessage: String = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LLM Endpoint")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                field(label: "Base URL", text: $baseURL, placeholder: "https://api.anthropic.com")
                field(label: "Auth Token", text: $token, placeholder: "sk-ant-... or cr_...", secure: true)
                field(label: "Model", text: $model, placeholder: "claude-opus-4-6")

                HStack {
                    Text("Format")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                    Picker("", selection: $format) {
                        Text("Anthropic").tag(LLMEndpointConfig.APIFormat.anthropic)
                        Text("OpenAI").tag(LLMEndpointConfig.APIFormat.openai)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            Divider()

            HStack {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(statusMessage.contains("Error") ? .red : .green)
                        .lineLimit(2)
                }
                Spacer()

                Button("Test") {
                    testConnection()
                }
                .disabled(testing || token.isEmpty)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func field(label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func save() {
        if let url = URL(string: baseURL) {
            LLMEndpointConfig.setBaseURL(url)
        }
        LLMEndpointConfig.setAPIFormat(format)
        LLMEndpointConfig.setDefaultModel(model)
        if !token.isEmpty {
            try? KeychainStore.storeLLMAuthToken(token)
        }
        statusMessage = "Saved. Restart app for changes to take full effect."
    }

    private func testConnection() {
        save()
        testing = true
        statusMessage = "Testing..."

        Task {
            do {
                let client = AnthropicClient()
                let response = try await client.complete(
                    system: "Reply with exactly: ok",
                    userMessage: "ping",
                    model: model,
                    temperature: 0,
                    maxTokens: 10
                )
                await MainActor.run {
                    testing = false
                    if response.text.lowercased().contains("ok") {
                        statusMessage = "Connected! Model: \(response.modelReported ?? model)"
                    } else {
                        statusMessage = "Got response: \(response.text.prefix(50))"
                    }
                }
            } catch {
                await MainActor.run {
                    testing = false
                    statusMessage = "Error: \(error.localizedDescription.prefix(100))"
                }
            }
        }
    }
}
