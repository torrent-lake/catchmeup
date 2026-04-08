import SwiftUI

/// Renders text that may still be streaming in, with a subtle animated
/// caret at the end while `isStreaming` is true. Selectable so the user
/// can copy the answer.
///
/// This isn't doing anything clever with per-token animation — SwiftUI's
/// natural re-render on `text` change already produces a smooth
/// incremental feel given how fast Claude streams. The caret is a visual
/// signal that generation is ongoing.
struct StreamingTokenText: View {
    let text: String
    let isStreaming: Bool

    @State private var caretVisible = true

    var body: some View {
        (Text(text) + caretText)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear(perform: startCaret)
            .onChange(of: isStreaming) { _, streaming in
                if streaming { startCaret() }
            }
    }

    private var caretText: Text {
        if isStreaming && caretVisible {
            return Text(" ▍")
                .foregroundStyle(Theme.neonCyan.opacity(0.85))
        }
        return Text("")
    }

    private func startCaret() {
        guard isStreaming else { return }
        Task { @MainActor in
            while isStreaming {
                try? await Task.sleep(nanoseconds: 500_000_000)
                caretVisible.toggle()
            }
            caretVisible = false
        }
    }
}
