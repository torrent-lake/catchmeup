import AppKit
import SwiftUI

enum HeatmapPaletteContext {
    case popover
    case statusIcon
}

enum HeatmapPalette {
    private struct Tuning {
        let idleAlpha: CGFloat
        let recordedBaseAlpha: CGFloat
        let recordedRangeAlpha: CGFloat
        let lowDiskRecordedAlpha: CGFloat
        let blockedRecordedAlpha: CGFloat
    }

    static func swiftUIColor(
        for bin: DayBin,
        state: RecorderState,
        context: HeatmapPaletteContext = .popover
    ) -> Color {
        Color(nsColor: nsColor(for: bin, state: state, context: context))
    }

    static func nsColor(
        for bin: DayBin,
        state: RecorderState,
        context: HeatmapPaletteContext = .statusIcon
    ) -> NSColor {
        let tuning = tuning(for: context)
        let idle = NSColor.white.withAlphaComponent(tuning.idleAlpha)

        switch state {
        case .recording, .recovering:
            guard bin.status == .recorded else { return idle }
            let intensity = min(1, max(0, bin.recordingIntensity))
            let alpha = tuning.recordedBaseAlpha + intensity * tuning.recordedRangeAlpha
            return Theme.neonCyanNS.withAlphaComponent(min(0.98, alpha))
        case .pausedLowDisk:
            guard bin.status == .recorded else { return idle }
            return Theme.lowDiskRedNS.withAlphaComponent(tuning.lowDiskRecordedAlpha)
        case .blockedNoPermission:
            guard bin.status == .recorded else { return idle }
            return Theme.gapAmberNS.withAlphaComponent(tuning.blockedRecordedAlpha)
        }
    }

    private static func tuning(for context: HeatmapPaletteContext) -> Tuning {
        switch context {
        case .popover:
            return Tuning(
                idleAlpha: 0.14,
                recordedBaseAlpha: 0.24,
                recordedRangeAlpha: 0.72,
                lowDiskRecordedAlpha: 0.88,
                blockedRecordedAlpha: 0.78
            )
        case .statusIcon:
            return Tuning(
                idleAlpha: 0.24,
                recordedBaseAlpha: 0.44,
                recordedRangeAlpha: 0.52,
                lowDiskRecordedAlpha: 0.94,
                blockedRecordedAlpha: 0.86
            )
        }
    }
}
