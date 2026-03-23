import AppKit

enum StatusTimelineImageFactory {
    private static let clockSegments = 12

    static func makeImage(bins: [DayBin], state: RecorderState, style: StatusIconStyle) -> NSImage {
        switch style {
        case .longStrip:
            return makeLongStripImage(bins: bins, state: state)
        case .clockBars12:
            return makeClockRingImage(bins: bins, state: state, radialNeedle: false)
        case .radialNeedle12:
            return makeClockRingImage(bins: bins, state: state, radialNeedle: true)
        }
    }

    private static func makeLongStripImage(bins: [DayBin], state: RecorderState) -> NSImage {
        let width: CGFloat = 108
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        let frame = CGRect(x: 1, y: 1, width: width - 2, height: height - 2)
        let backgroundPath = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.18).setFill()
        backgroundPath.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        backgroundPath.lineWidth = 0.6
        backgroundPath.stroke()

        let glow = NSShadow()
        glow.shadowBlurRadius = 4
        glow.shadowColor = colorForState(state).withAlphaComponent(0.56)
        glow.shadowOffset = .zero
        glow.set()

        let binsToDraw = bins.isEmpty ? DayBinMapper.emptyBins(for: Date()) : bins
        let barWidth = frame.width / CGFloat(max(1, binsToDraw.count))
        let barHeight = frame.height - 4

        for (index, bin) in binsToDraw.enumerated() {
            let x = frame.origin.x + CGFloat(index) * barWidth
            let y = frame.origin.y + 2
            let rect = CGRect(x: x, y: y, width: max(0.65, barWidth - 0.1), height: barHeight)
            color(for: bin, state: state, context: .statusIcon).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
        }

        return image
    }

    private static func makeClockRingImage(bins: [DayBin], state: RecorderState, radialNeedle: Bool) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let center = CGPoint(x: size / 2, y: size / 2)
        let ring = makeClockData(from: bins.isEmpty ? DayBinMapper.emptyBins(for: Date()) : bins)
        let tickWidth: CGFloat = radialNeedle ? 1.9 : 3.9
        let tickHeight: CGFloat = radialNeedle ? 4.8 : 2.3
        let radius: CGFloat = radialNeedle ? 5.5 : 5.7

        for index in 0..<clockSegments {
            // 0:00 at top, then advance clockwise around a 24h ring.
            let angle = -(Double(index) / Double(clockSegments)) * (2 * Double.pi)
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(angle))
            let y = radialNeedle ? (radius - tickHeight / 2) : radius
            let rect = CGRect(x: -tickWidth / 2, y: y, width: tickWidth, height: tickHeight)
            context.setFillColor(color(for: ring[index], state: state, context: .statusIcon).cgColor)
            context.fill(rect)
            context.restoreGState()
        }
        return image
    }

    private static func makeClockData(from bins: [DayBin]) -> [DayBin] {
        guard !bins.isEmpty else { return [] }
        var output: [DayBin] = []
        output.reserveCapacity(clockSegments)

        for segment in 0..<clockSegments {
            let start = Int(Double(segment) / Double(clockSegments) * Double(bins.count))
            let end = Int(Double(segment + 1) / Double(clockSegments) * Double(bins.count))
            let slice = bins[start..<max(start + 1, end)]

            let status: DayBinStatus
            if slice.contains(where: { $0.status == .recorded }) {
                status = .recorded
            } else if slice.contains(where: { $0.status == .gap }) {
                status = .gap
            } else {
                status = .none
            }

            let intensity = {
                let values = slice.filter { $0.status == .recorded }.map(\.recordingIntensity)
                guard !values.isEmpty else { return 0.0 }
                return values.reduce(0, +) / Double(values.count)
            }()

            output.append(
                DayBin(
                    index0to95: segment,
                    startAt: slice.first?.startAt ?? Date(),
                    endAt: slice.last?.endAt ?? Date(),
                    status: status,
                    recordingIntensity: intensity
                )
            )
        }
        return output
    }

    private static func colorForState(_ state: RecorderState) -> NSColor {
        switch state {
        case .recording:
            return Theme.neonCyanNS
        case .pausedLowDisk:
            return Theme.lowDiskRedNS
        case .blockedNoPermission:
            return Theme.gapAmberNS
        case .recovering:
            return NSColor.white.withAlphaComponent(0.75)
        }
    }

    private static func color(for bin: DayBin, state: RecorderState, context: HeatmapPaletteContext) -> NSColor {
        HeatmapPalette.nsColor(for: bin, state: state, context: context)
    }
}
