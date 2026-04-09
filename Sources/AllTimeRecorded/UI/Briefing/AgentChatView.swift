import AppKit
import SwiftUI

/// The on-demand agent chat UI. Lives inside the floating `RecallPanel`
/// overlay that the user already knows from AllTimeRecorded. Single-turn
/// for Phase 2 Slice 2 — each submit replaces the previous answer.
///
/// Visual language: matches `PopoverContentView` and `MainDashboardView` —
/// glass backdrop, neonCyan accent, dark tint, rounded 18pt corners.
struct AgentChatView: View {
    @ObservedObject var viewModel: AgentChatViewModel
    var onClose: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            GlassMaterialView()
            Color.black.opacity(0.12)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.black.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)

            VStack(alignment: .leading, spacing: 10) {
                header
                answerArea
                inputBar
            }
            .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Theme.neonCyan.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.white.opacity(0.05), radius: 14, x: 0, y: 5)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                inputFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(headerDotColor)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.95 : 0.45)
            Text("Ask CatchMeUp")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var headerDotColor: Color {
        switch viewModel.state {
        case .idle:                  return Theme.neonCyan.opacity(0.5)
        case .retrieving, .streaming: return Theme.neonCyan
        case .complete:              return Theme.neonCyan.opacity(0.85)
        case .error:                 return Theme.lowDiskRed
        }
    }

    // MARK: - Answer area

    private var answerArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.lastQuestion.isEmpty {
                    questionBubble
                }
                stateContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.neonCyan.opacity(0.12), lineWidth: 0.7)
        )
    }

    private var questionBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("You")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.neonCyan.opacity(0.55))
                .frame(width: 28, alignment: .leading)
            Text(viewModel.lastQuestion)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle:
            idleHint

        case .retrieving(let sourceIDs):
            retrievingHint(sourceIDs: sourceIDs)

        case .streaming(let text, let chunks):
            answerBody(text: text, chunks: chunks, isStreaming: true)

        case .complete(let text, let chunks):
            answerBody(text: text, chunks: chunks, isStreaming: false)

        case .error(let message):
            errorBlock(message: message)
        }
    }

    private var idleHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about anything in your mail, chats, meetings, or files.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Text("Example: \"what did Alice say about the Q3 review?\"")
                .font(.system(.caption2, design: .rounded).italic())
                .foregroundStyle(.white.opacity(0.35))

            // Quick action buttons
            HStack(spacing: 6) {
                quickActionButton(
                    icon: "sun.max",
                    label: "Tomorrow\u{2019}s brief",
                    action: { viewModel.askProactiveBrief() }
                )
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(.caption2, design: .rounded))
            }
            .foregroundStyle(Theme.neonCyan.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.neonCyan.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.neonCyan.opacity(0.25), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    private func retrievingHint(sourceIDs: [String]) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(Theme.neonCyan)
            Text(sourceIDs.isEmpty
                 ? "Searching your history…"
                 : "Searching \(sourceIDs.joined(separator: ", "))…")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func answerBody(text: String, chunks: [SourceChunk], isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text("•••")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.neonCyan.opacity(0.55))
                    .frame(width: 28, alignment: .leading)
                StreamingTokenText(text: text, isStreaming: isStreaming)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            if !chunks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isStreaming ? "Sources in context" : "Cited")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(chunks.enumerated()), id: \.element.id) { index, chunk in
                            CitationChip(chunk: chunk, displayID: index + 1)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            // File drag-and-drop zone (when file results are available)
            if !viewModel.fileResults.isEmpty && !isStreaming {
                fileDragZone
            }

            // Feedback buttons (shown only when answer is complete)
            if !isStreaming {
                feedbackBar
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Feedback bar

    private var feedbackBar: some View {
        HStack(spacing: 8) {
            if let given = viewModel.feedbackGiven {
                Text(given == .thumbsUp ? "Thanks for the feedback!" : "We'll do better.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Text("Was this helpful?")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                feedbackButton(icon: "hand.thumbsup", rating: .thumbsUp)
                feedbackButton(icon: "hand.thumbsdown", rating: .thumbsDown)
                feedbackButton(icon: "arrow.triangle.branch", rating: .wrongSource, label: "Wrong source")
            }
            Spacer()
        }
    }

    private func feedbackButton(icon: String, rating: AuditEntry.Rating, label: String? = nil) -> some View {
        Button {
            viewModel.giveFeedback(rating)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                if let label {
                    Text(label)
                        .font(.system(.caption2, design: .rounded))
                }
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - File drag zone

    private var fileDragZone: some View {
        let fileURLs = viewModel.fileResults.compactMap { chunk -> URL? in
            guard let uri = chunk.originURI else { return nil }
            return URL(string: uri)
        }

        return ZStack {
            // Invisible AppKit drag source covering the visual element
            MultiFileDragView(fileURLs: fileURLs)
                .frame(maxWidth: .infinity)
                .frame(height: 52)

            // Visual element
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.neonCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fileURLs.count) files gathered")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Drag to upload to any app")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.neonCyan.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.neonCyan.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
    }

    private func errorBlock(message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.lowDiskRed.opacity(0.85))
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .textSelection(.enabled)
        }
        .padding(10)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField("Ask anything…", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .focused($inputFocused)
                .onSubmit {
                    viewModel.submit()
                }
                .disabled(viewModel.isBusy)

            Button {
                if viewModel.isBusy {
                    viewModel.cancel()
                } else {
                    viewModel.submit()
                }
            } label: {
                Image(systemName: viewModel.isBusy ? "stop.fill" : "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(Theme.neonCyan.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isBusy && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.neonCyan.opacity(inputFocused ? 0.5 : 0.18), lineWidth: 0.9)
        )
    }
}

// MARK: - FlowLayout helper

/// Simple flow layout that wraps its subviews onto multiple rows when the
/// container is too narrow to fit them on one row. Phase 2 Slice 2 helper
/// for the citation chip strip.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 400
        let arrangement = arrange(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: maxWidth, height: arrangement.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        let arrangement = arrange(subviews: subviews, maxWidth: maxWidth)
        for (index, frame) in arrangement.frames.enumerated() {
            let origin = CGPoint(
                x: bounds.minX + frame.origin.x,
                y: bounds.minY + frame.origin.y
            )
            subviews[index].place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], totalHeight: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (frames, y + rowHeight)
    }
}
