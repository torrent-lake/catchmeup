import AppKit
import SwiftUI

/// A clickable reference to a retrieved `SourceChunk`. Shows source icon +
/// display ID + a short title. Click opens a popover with the full chunk
/// body so the user can verify the citation.
///
/// Part of the citation rendering contract: every factual claim in an
/// answer should be followed by `[N]`, and there must be a corresponding
/// chip with the same N somewhere in the chip row. The UI does not
/// yet auto-highlight the matching chip when the user hovers over `[N]`
/// in the answer — Phase 3 will add that link.
struct CitationChip: View {
    let chunk: SourceChunk
    let displayID: Int

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.neonCyan.opacity(0.9))
                Text("[\(displayID)]")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(shortTitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let label = relativeDateLabel {
                    Text(label)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.neonCyan.opacity(0.22), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetail, arrowEdge: .top) {
            CitationDetailPopover(chunk: chunk, displayID: displayID)
        }
    }

    private var shortTitle: String {
        let base = chunk.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return chunk.sourceID }
        let words = base.split(separator: " ").prefix(5).joined(separator: " ")
        return String(words.prefix(32))
    }

    private var iconName: String {
        switch chunk.sourceID {
        case "mail":        return "envelope.fill"
        case "wechat":      return "bubble.left.and.bubble.right.fill"
        case "transcripts": return "waveform"
        case "files":       return "doc.fill"
        case "calendar":    return "calendar"
        default:            return "circle.fill"
        }
    }

    private var relativeDateLabel: String? {
        guard let ts = chunk.timestamp else { return nil }
        let interval = Date().timeIntervalSince(ts)
        let days = interval / 86_400
        if days < 1 { return "today" }
        if days < 2 { return "yesterday" }
        if days < 7 { return "\(Int(days))d" }
        if days < 30 { return "\(Int(days / 7))w" }
        if days < 365 { return "\(Int(days / 30))mo" }
        return "\(Int(days / 365))y"
    }
}

/// Full-body popover shown when a `CitationChip` is clicked. Renders the
/// raw chunk text with a tight max size so huge chunks don't blow out the
/// screen.
struct CitationDetailPopover: View {
    let chunk: SourceChunk
    let displayID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("[\(displayID)]")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.neonCyan)
                Text(chunk.sourceID.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                if let ts = chunk.timestamp {
                    Text(Self.fullDate(ts))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            }
            Text(chunk.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            ScrollView {
                Text(chunk.body)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .frame(maxWidth: 420, maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
        }
        .padding(12)
        .frame(width: 440)
        .background(Color.black.opacity(0.88))
    }

    private static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
