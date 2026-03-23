import AppKit
import Foundation
import Testing
@testable import AllTimeRecorded

struct HeatmapPaletteTests {
    @Test
    func gapAndNoneShareSameColorAcrossContexts() {
        let gapBin = makeBin(index: 12, status: .gap, intensity: 0)
        let noneBin = makeBin(index: 13, status: .none, intensity: 0)

        for context in [HeatmapPaletteContext.popover, .statusIcon] {
            let gap = HeatmapPalette.nsColor(for: gapBin, state: .recording, context: context)
            let none = HeatmapPalette.nsColor(for: noneBin, state: .recording, context: context)
            #expect(colorsClose(gap, none))
        }
    }

    @Test
    func recordedIntensityChangesHeatmapStrength() {
        let soft = makeBin(index: 20, status: .recorded, intensity: 0.15)
        let loud = makeBin(index: 20, status: .recorded, intensity: 0.95)

        let softColor = HeatmapPalette.nsColor(for: soft, state: .recording, context: .popover)
        let loudColor = HeatmapPalette.nsColor(for: loud, state: .recording, context: .popover)

        let (_, _, _, softAlpha) = rgba(softColor)
        let (_, _, _, loudAlpha) = rgba(loudColor)
        #expect(loudAlpha > softAlpha)
    }

    private func makeBin(index: Int, status: DayBinStatus, intensity: Double) -> DayBin {
        let start = Date(timeIntervalSince1970: TimeInterval(index) * 900)
        return DayBin(
            index0to95: index,
            startAt: start,
            endAt: start.addingTimeInterval(900),
            status: status,
            recordingIntensity: intensity
        )
    }

    private func rgba(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let value = color.usingColorSpace(.sRGB) ?? color
        return (value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent)
    }

    private func colorsClose(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.002) -> Bool {
        let a = rgba(lhs)
        let b = rgba(rhs)
        return abs(a.0 - b.0) <= tolerance
            && abs(a.1 - b.1) <= tolerance
            && abs(a.2 - b.2) <= tolerance
            && abs(a.3 - b.3) <= tolerance
    }
}
