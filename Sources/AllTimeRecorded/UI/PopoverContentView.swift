import AppKit
import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var model: AppModel
    var onOpenMainWindow: () -> Void = {}
    @State private var pulse = false

    var body: some View {
        ZStack {
            GlassMaterialView()
            Color.black.opacity(0.1)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
            VStack(alignment: .leading, spacing: 10) {
                header
                timeline
                statsRow
                footer
            }
            .padding(14)
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
        .frame(width: 448, height: 258)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AllTimeRecorded")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text("Open-lid audio, local text pickup")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button(action: onOpenMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Open Main Window")

            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor.opacity(pulse && model.snapshot.state == .recording ? 1 : 0.55))
                    .frame(width: 8, height: 8)
                Text(model.stateTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(stateColor)
        }
    }

    private var timeline: some View {
        HStack {
            Spacer(minLength: 0)
            TimelineHeatmapPanel(
                bins: model.snapshot.bins,
                state: model.snapshot.state,
                arcs: []
            )
            Spacer(minLength: 0)
        }
    }

    private var statsRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                statCard(title: "Recorded", value: model.recordedTodayLabel(at: context.date), tint: Theme.neonCyan)
                statCard(title: "Gap", value: model.gapTodayLabel(at: context.date), tint: Theme.gapAmber)
                statCard(title: "Free", value: model.freeSpaceLabel, tint: .white)
            }
        }
    }

    private var footer: some View {
        Text("Forced sleep can interrupt recording; app auto-resumes and paints the gap.")
            .font(.system(.caption2, design: .rounded))
            .lineLimit(2)
            .foregroundStyle(.white.opacity(0.62))
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var stateColor: Color {
        switch model.snapshot.state {
        case .recording:
            return Theme.neonCyan
        case .pausedLowDisk:
            return Theme.lowDiskRed
        case .blockedNoPermission:
            return Theme.gapAmber
        case .recovering:
            return .white
        }
    }

}
