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

    // MARK: - Multi-source context density mode

    /// Returns a color reflecting all context sources present in this bin.
    /// Recording keeps its cyan base. Context sources add a subtle tint.
    /// If ONLY context (no recording), the dominant source color is used.
    static func contextDensityColor(
        for bin: DayBin,
        state: RecorderState,
        context: HeatmapPaletteContext = .popover
    ) -> NSColor {
        let tuning = tuning(for: context)
        let idle = NSColor.white.withAlphaComponent(tuning.idleAlpha)
        let hasRecording = bin.status == .recorded
        let hasContext = bin.hasContextDensity

        // Nothing at all → idle
        guard hasRecording || hasContext else { return idle }

        // Recording only, no context → original cyan palette
        if hasRecording && !hasContext {
            return nsColor(for: bin, state: state, context: context)
        }

        // Find the dominant context source
        let contextSources: [(color: NSColor, density: Double)] = [
            (Theme.calendarAmberNS, bin.calendarDensity),
            (Theme.emailVioletNS, bin.emailDensity),
            (Theme.chatGreenNS, bin.chatDensity),
            (Theme.filePinkNS, bin.fileDensity),
            (Theme.reminderBlueNS, bin.reminderDensity),
        ].filter { $0.density > 0 }

        guard let dominant = contextSources.max(by: { $0.density < $1.density }) else {
            // Shouldn't happen if hasContext is true, but fallback
            return hasRecording ? nsColor(for: bin, state: state, context: context) : idle
        }

        if hasRecording {
            // BOTH recording + context: use cyan as base, tint toward context color
            let intensity = max(0.08, min(1, bin.recordingIntensity))
            let contextStrength = min(1.0, dominant.density * 0.4) // subtle tint
            let blended = blendWeighted([
                (Theme.neonCyanNS, intensity * (1.0 - contextStrength)),
                (dominant.color, contextStrength),
            ])
            let alpha = tuning.recordedBaseAlpha + intensity * tuning.recordedRangeAlpha
            return blended.withAlphaComponent(min(0.98, alpha))
        } else {
            // Context only, no recording: use context source color directly
            let alpha = tuning.recordedBaseAlpha + dominant.density * tuning.recordedRangeAlpha * 0.7
            return dominant.color.withAlphaComponent(min(0.85, alpha))
        }
    }

    static func swiftUIContextDensityColor(
        for bin: DayBin,
        state: RecorderState,
        context: HeatmapPaletteContext = .popover
    ) -> Color {
        Color(nsColor: contextDensityColor(for: bin, state: state, context: context))
    }

    /// Weighted RGB blend. Each color contributes proportionally to its weight.
    private static func blendWeighted(_ components: [(color: NSColor, weight: Double)]) -> NSColor {
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var totalW: CGFloat = 0

        for (color, weight) in components {
            let c = color.usingColorSpace(.sRGB) ?? color
            let w = CGFloat(weight)
            totalR += c.redComponent * w
            totalG += c.greenComponent * w
            totalB += c.blueComponent * w
            totalW += w
        }

        guard totalW > 0 else {
            return NSColor.white
        }

        return NSColor(
            srgbRed: totalR / totalW,
            green: totalG / totalW,
            blue: totalB / totalW,
            alpha: 1.0
        )
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
