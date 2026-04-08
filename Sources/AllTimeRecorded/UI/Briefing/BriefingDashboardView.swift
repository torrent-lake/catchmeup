import AppKit
import SwiftUI

/// The primary content of the main glass window as of Phase 1.
///
/// This is the user-facing briefing surface. It is NOT a developer view.
/// Everything here is designed for the end user: the 4 panels correspond
/// to the four sections of every CatchMeUp briefing (Today's Highlights,
/// Action Items, You May Have Missed, Looking Ahead), and the empty states
/// communicate what each panel will show, not what phase of development
/// we're in.
///
/// Developer affordances (probes, raw output, subsystem tests) live in the
/// status bar's right-click menu under `#if DEBUG` — see `StatusBarController`.
struct BriefingDashboardView: View {
    @ObservedObject var appModel: AppModel

    var showsWindowControls: Bool = false
    var onCloseWindow: (() -> Void)? = nil
    var onMinimizeWindow: (() -> Void)? = nil
    var onZoomWindow: (() -> Void)? = nil
    var onToggleRecall: (() -> Void)? = nil

    @State private var pulse = false

    var body: some View {
        ZStack {
            GlassMaterialView()
            Color.black.opacity(0.1)
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

            VStack(alignment: .leading, spacing: 14) {
                header
                watchingStatus
                panelsGrid
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.34), Theme.neonCyan.opacity(0.18)],
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
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CatchMeUp")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text("A trusted system for everything you didn't write down.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            recordingModeBadge
        }
    }

    private var recordingModeBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(recordingModeColor)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 1.0 : 0.5)
            VStack(alignment: .trailing, spacing: 2) {
                Text(appModel.recordingMode.displayName)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(appModel.recordingMode.shortDescription)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var recordingModeColor: Color {
        switch appModel.recordingMode {
        case .gentle: return Theme.neonCyan
        case .manual: return Color.white.opacity(0.55)
        case .rogue:  return Theme.lowDiskRed
        }
    }

    // MARK: - Watching status line

    private var watchingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.neonCyan)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 0.95 : 0.45)
            Text("Waiting for your first briefing — it will appear here after your next calendar event or the evening digest.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Four-panel grid

    private var panelsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                briefingPanel(
                    title: "Today's Highlights",
                    subtitle: "Your day so far"
                ) {
                    emptyStateText(
                        "Nothing yet. As your day unfolds, the 3–5 most important things that happened across your meetings, mail, and conversations will be drafted here."
                    )
                }
                briefingPanel(
                    title: "Action Items",
                    subtitle: "What you committed to"
                ) {
                    emptyStateText(
                        "Nothing captured yet. When you say \u{201c}I\u{2019}ll send that by Friday\u{201d} in a meeting or email, CatchMeUp extracts it here and ranks by urgency."
                    )
                }
            }
            HStack(spacing: 10) {
                briefingPanel(
                    title: "You May Have Missed",
                    subtitle: "Background signals"
                ) {
                    emptyStateText(
                        "Nothing flagged. Background meeting chatter, unread mail, and drive-by group messages that are worth surfacing will land here."
                    )
                }
                briefingPanel(
                    title: "Looking Ahead",
                    subtitle: "Tomorrow's context"
                ) {
                    emptyStateText(
                        "Nothing scheduled. Before each meeting tomorrow, CatchMeUp will pre-brief you with every relevant prior email, message, and past transcript."
                    )
                }
            }
        }
    }

    private func briefingPanel<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(subtitle)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.neonCyan.opacity(0.55))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.neonCyan.opacity(0.14), lineWidth: 0.8)
        )
    }

    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
