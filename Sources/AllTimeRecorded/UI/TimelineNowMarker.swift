import Foundation
import SwiftUI

enum TimelineGeometry {
    static let totalBins = 96
    static let binSeconds: TimeInterval = 15 * 60

    static func currentBinIndex(at now: Date, calendar: Calendar = .current) -> Int {
        let dayStart = calendar.startOfDay(for: now)
        let offset = max(0, now.timeIntervalSince(dayStart))
        let raw = Int(offset / binSeconds)
        return min(totalBins - 1, max(0, raw))
    }

    static func binBottomCenter(
        index: Int,
        columns: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        spacing: CGFloat,
        origin: CGPoint = .zero
    ) -> CGPoint {
        let clamped = min(totalBins - 1, max(0, index))
        let row = clamped / columns
        let column = clamped % columns
        let stepX = cellWidth + spacing
        let stepY = cellHeight + spacing
        return CGPoint(
            x: origin.x + CGFloat(column) * stepX + cellWidth / 2,
            y: origin.y + CGFloat(row) * stepY + cellHeight
        )
    }

    static func binCenter(
        index: Int,
        columns: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        spacing: CGFloat,
        origin: CGPoint = .zero
    ) -> CGPoint {
        let clamped = min(totalBins - 1, max(0, index))
        let row = clamped / columns
        let column = clamped % columns
        let stepX = cellWidth + spacing
        let stepY = cellHeight + spacing
        return CGPoint(
            x: origin.x + CGFloat(column) * stepX + cellWidth / 2,
            y: origin.y + CGFloat(row) * stepY + cellHeight / 2
        )
    }

    static func nowPointerPoints(
        target: CGPoint,
        canvasWidth: CGFloat,
        markerHeight: CGFloat
    ) -> (start: CGPoint, midA: CGPoint, midB: CGPoint, end: CGPoint, startFromLeft: Bool) {
        let startFromLeft = target.x <= canvasWidth * 0.5
        let sideInset: CGFloat = 20
        let startX = startFromLeft ? sideInset : canvasWidth - sideInset
        let startY = max(7, min(12, markerHeight * 0.14))
        let start = CGPoint(x: startX, y: startY)
        let horizontalLead = max(18, min(36, abs(target.x - startX) * 0.34))
        let midA = CGPoint(
            x: startFromLeft ? startX + horizontalLead : startX - horizontalLead,
            y: startY
        )
        let midB = CGPoint(
            x: target.x + (startFromLeft ? -8 : 8),
            y: max(startY + 8, target.y - 10)
        )
        let end = target
        return (start, midA, midB, end, startFromLeft)
    }
}

struct TimelineNowMarker: View {
    let now: Date
    let columns: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let spacing: CGFloat
    let tint: Color
    let canvasWidth: CGFloat
    let gridOriginX: CGFloat

    var body: some View {
        let index = TimelineGeometry.currentBinIndex(at: now)
        let target = TimelineGeometry.binCenter(
            index: index,
            columns: columns,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            spacing: spacing,
            origin: CGPoint(x: gridOriginX, y: 0)
        )

        GeometryReader { proxy in
            let points = TimelineGeometry.nowPointerPoints(
                target: target,
                canvasWidth: proxy.size.width,
                markerHeight: proxy.size.height
            )
            let labelX = points.startFromLeft ? points.start.x - 11 : points.start.x + 11

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: points.start)
                    path.addLine(to: points.midA)
                    path.addLine(to: points.midB)
                    path.addLine(to: points.end)
                }
                .stroke(
                    tint.opacity(0.5),
                    style: StrokeStyle(lineWidth: 0.55, lineCap: .round, lineJoin: .round)
                )

                Text("Now")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.72))
                    .position(x: labelX, y: points.start.y)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(width: canvasWidth)
        .allowsHitTesting(false)
    }
}
