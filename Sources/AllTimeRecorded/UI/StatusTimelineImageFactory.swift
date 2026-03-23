import AppKit

enum StatusTimelineImageFactory {
    static func makeImage(bins: [DayBin], state: RecorderState) -> NSImage {
        let width: CGFloat = 108
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        let frame = CGRect(x: 1, y: 1, width: width - 2, height: height - 2)
        let backgroundPath = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.08).setFill()
        backgroundPath.fill()

        let glow = NSShadow()
        glow.shadowBlurRadius = 4
        glow.shadowColor = colorForState(state).withAlphaComponent(0.45)
        glow.shadowOffset = .zero
        glow.set()

        let binsToDraw = bins.isEmpty ? DayBinMapper.emptyBins(for: Date()) : bins
        let barWidth = frame.width / CGFloat(binsToDraw.count)
        let barHeight = frame.height - 4

        for (index, bin) in binsToDraw.enumerated() {
            let x = frame.origin.x + CGFloat(index) * barWidth
            let y = frame.origin.y + 2
            let rect = CGRect(x: x, y: y, width: max(1, barWidth - 0.15), height: barHeight)
            colorForBin(bin, state: state).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
        }

        return image
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

    private static func colorForBin(_ bin: DayBin, state: RecorderState) -> NSColor {
        switch state {
        case .pausedLowDisk:
            return bin.status == .none ? Theme.idleGrayNS : Theme.lowDiskRedNS.withAlphaComponent(bin.status == .gap ? 0.75 : 0.95)
        case .blockedNoPermission:
            return bin.status == .none ? Theme.idleGrayNS : Theme.gapAmberNS.withAlphaComponent(0.9)
        case .recovering, .recording:
            switch bin.status {
            case .recorded:
                return heatColor(intensity: bin.recordingIntensity)
            case .gap:
                return Theme.gapAmberNS.withAlphaComponent(0.9)
            case .none:
                return Theme.idleGrayNS
            }
        }
    }

    private static func heatColor(intensity: Double) -> NSColor {
        let value = min(1, max(0, intensity))
        if value < 0.5 {
            let lighter = Theme.neonCyanNS.blended(withFraction: (0.5 - value) * 1.4, of: NSColor.white) ?? Theme.neonCyanNS
            return lighter.withAlphaComponent(0.9)
        }
        let darker = Theme.neonCyanNS.blended(withFraction: (value - 0.5) * 0.8, of: NSColor.black) ?? Theme.neonCyanNS
        return darker.withAlphaComponent(0.98)
    }
}
