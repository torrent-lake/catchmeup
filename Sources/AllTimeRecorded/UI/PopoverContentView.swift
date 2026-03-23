import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var model: AppModel
    @State private var pulse = false

    private let heatmapColumns = 24
    private let heatmapSpacing: CGFloat = 2

    var body: some View {
        ZStack {
            GlassMaterialView()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Theme.neonCyan.opacity(0.06),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                .stroke(Color.white.opacity(0.17), lineWidth: 1)
        )
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
                Text("Heatmap reflects voice activity per 15-minute bin")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor.opacity(pulse && model.snapshot.state == .recording ? 1 : 0.55))
                    .frame(width: 8, height: 8)
                Text(model.stateTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.2), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(stateColor)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                let cell = max(7, floor((geometry.size.width - CGFloat(heatmapColumns - 1) * heatmapSpacing) / CGFloat(heatmapColumns)))
                let columns = Array(repeating: GridItem(.fixed(cell), spacing: heatmapSpacing), count: heatmapColumns)

                LazyVGrid(columns: columns, spacing: heatmapSpacing) {
                    ForEach(heatmapBins) { bin in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: bin))
                            .frame(width: cell, height: cell)
                    }
                }
            }
            .frame(height: 72)
            .clipped()

            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statCard(title: "Recorded", value: model.recordedTodayLabel, tint: Theme.neonCyan)
            statCard(title: "Gap", value: model.gapTodayLabel, tint: Theme.gapAmber)
            statCard(title: "Free", value: model.freeSpaceLabel, tint: .white)
        }
    }

    private var footer: some View {
        Text("Forced sleep can interrupt recording; app auto-resumes and paints the gap.")
            .font(.system(.caption2, design: .rounded))
            .lineLimit(2)
            .foregroundStyle(.white.opacity(0.53))
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
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var heatmapBins: [DayBin] {
        let bins = model.snapshot.bins
        guard bins.count == 96 else { return bins }

        var ordered: [DayBin] = []
        ordered.reserveCapacity(96)

        for quarter in 0..<4 {
            for hour in 0..<24 {
                ordered.append(bins[hour * 4 + quarter])
            }
        }
        return ordered
    }

    private func color(for bin: DayBin) -> Color {
        switch model.snapshot.state {
        case .pausedLowDisk:
            if bin.status == .none { return Theme.idleGray }
            return Theme.lowDiskRed.opacity(bin.status == .gap ? 0.72 : 0.95)
        case .blockedNoPermission:
            return bin.status == .none ? Theme.idleGray : Theme.gapAmber.opacity(0.85)
        case .recording, .recovering:
            switch bin.status {
            case .recorded:
                return heatColor(intensity: bin.recordingIntensity)
            case .gap:
                return Theme.gapAmber.opacity(0.9)
            case .none:
                return Theme.idleGray
            }
        }
    }

    private func heatColor(intensity: Double) -> Color {
        let value = max(0, min(1, intensity))
        let light = (r: 0.78, g: 0.97, b: 0.99)
        let base = (r: 0.28, g: 0.90, b: 0.95)
        let dark = (r: 0.05, g: 0.52, b: 0.58)

        if value < 0.5 {
            let t = value / 0.5
            return mixedColor(from: light, to: base, t: t, alpha: 0.88)
        }
        let t = (value - 0.5) / 0.5
        return mixedColor(from: base, to: dark, t: t, alpha: 0.96)
    }

    private func mixedColor(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        t: Double,
        alpha: Double
    ) -> Color {
        let clamped = max(0, min(1, t))
        return Color(
            red: from.r + (to.r - from.r) * clamped,
            green: from.g + (to.g - from.g) * clamped,
            blue: from.b + (to.b - from.b) * clamped,
            opacity: alpha
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

