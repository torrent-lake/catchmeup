import SwiftUI

/// Renders text that may still be streaming in, with basic Markdown support
/// (bold, italic, code) and a subtle animated caret while streaming.
struct StreamingTokenText: View {
    let text: String
    let isStreaming: Bool

    @State private var caretVisible = true

    var body: some View {
        (renderMarkdown(text) + caretText)
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

    /// Parse basic Markdown: **bold**, *italic*, `code`, [N] citations.
    private func renderMarkdown(_ input: String) -> Text {
        var result = Text("")
        var remaining = input[input.startIndex...]

        while !remaining.isEmpty {
            // **bold**
            if remaining.hasPrefix("**"),
               let closeRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                   .range(of: "**") {
                let boldStart = remaining.index(remaining.startIndex, offsetBy: 2)
                let boldText = String(remaining[boldStart..<closeRange.lowerBound])
                result = result + Text(boldText).bold()
                remaining = remaining[closeRange.upperBound...]
                continue
            }

            // *italic* (but not **)
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**"),
               let closeIdx = remaining[remaining.index(after: remaining.startIndex)...]
                   .firstIndex(of: "*") {
                let italicStart = remaining.index(after: remaining.startIndex)
                let italicText = String(remaining[italicStart..<closeIdx])
                result = result + Text(italicText).italic()
                remaining = remaining[remaining.index(after: closeIdx)...]
                continue
            }

            // `code`
            if remaining.hasPrefix("`"),
               let closeIdx = remaining[remaining.index(after: remaining.startIndex)...]
                   .firstIndex(of: "`") {
                let codeStart = remaining.index(after: remaining.startIndex)
                let codeText = String(remaining[codeStart..<closeIdx])
                result = result + Text(codeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan.opacity(0.9))
                remaining = remaining[remaining.index(after: closeIdx)...]
                continue
            }

            // [N] citation — cyan highlight
            if remaining.hasPrefix("["),
               let closeIdx = remaining.firstIndex(of: "]") {
                let inner = remaining[remaining.index(after: remaining.startIndex)..<closeIdx]
                if inner.allSatisfy({ $0.isNumber }) && inner.count <= 2 {
                    result = result + Text("[\(inner)]")
                        .foregroundStyle(Theme.neonCyan)
                        .bold()
                    remaining = remaining[remaining.index(after: closeIdx)...]
                    continue
                }
            }

            // Plain character
            result = result + Text(String(remaining.first!))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }

    private var caretText: Text {
        if isStreaming && caretVisible {
            return Text(" \u{258D}")
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
