import SwiftUI

struct TimelineHeatmapPanel: View {
    let bins: [DayBin]
    let state: RecorderState
    let arcs: [CalendarArcSegment]
    var onHoverChanged: ((CalendarArcSegment?, CGPoint?) -> Void)? = nil
    var onArcTapped: ((CalendarArcSegment?, CGPoint?) -> Void)? = nil
    var onBinHoverChanged: ((DayBin?, CGPoint?) -> Void)? = nil
    var highlightedRanges: [DateInterval] = []
    var cellWidth: CGFloat = 3
    var cellHeight: CGFloat = 18
    var cellSpacing: CGFloat = 1
    var horizontalPadding: CGFloat = 56
    var showsAxisMarkers = true
    var showsNowMarker = true

    private let columnsCount = 24
    private let rowsCount = 4

    private var gridWidth: CGFloat {
        CGFloat(columnsCount) * cellWidth + CGFloat(columnsCount - 1) * cellSpacing
    }

    private var gridHeight: CGFloat {
        CGFloat(rowsCount) * cellHeight + CGFloat(rowsCount - 1) * cellSpacing
    }

    private var canvasWidth: CGFloat {
        gridWidth + horizontalPadding
    }

    private var gridOriginX: CGFloat {
        (canvasWidth - gridWidth) / 2
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: cellSpacing), count: columnsCount)
    }

    private var displayBins: [DayBin] {
        bins.isEmpty ? DayBinMapper.emptyBins(for: Date()) : bins
    }

    /// Use context-density blended color when a bin has multi-source data;
    /// otherwise fall back to the original single-source palette.
    private func binColor(for bin: DayBin) -> Color {
        if bin.hasContextDensity {
            return HeatmapPalette.swiftUIContextDensityColor(for: bin, state: state, context: .popover)
        }
        return HeatmapPalette.swiftUIColor(for: bin, state: state, context: .popover)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsAxisMarkers {
                Text("☀︎")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(width: canvasWidth, alignment: .center)
            }

            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: columns, spacing: cellSpacing) {
                    ForEach(displayBins) { bin in
                        RoundedRectangle(cornerRadius: max(1, cellWidth * 0.28), style: .continuous)
                            .fill(binColor(for: bin))
                            .frame(height: cellHeight)
                    }
                }
                .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                .offset(x: gridOriginX)

                CalendarHighlighterOverlay(
                    bins: displayBins,
                    arcs: arcs,
                    columnsCount: columnsCount,
                    rowsCount: rowsCount,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    spacing: cellSpacing,
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    gridOriginX: gridOriginX,
                    onHoverChanged: onHoverChanged,
                    onArcTapped: onArcTapped,
                    onBinHoverChanged: onBinHoverChanged
                )
                .frame(width: canvasWidth, height: gridHeight, alignment: .topLeading)

                if !highlightedRanges.isEmpty {
                    QueryHighlightOverlay(
                        bins: displayBins,
                        highlightedRanges: highlightedRanges,
                        columnsCount: columnsCount,
                        rowsCount: rowsCount,
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        spacing: cellSpacing,
                        gridOriginX: gridOriginX
                    )
                    .frame(width: canvasWidth, height: gridHeight, alignment: .topLeading)
                    .allowsHitTesting(false)
                }

                if showsNowMarker {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TimelineNowMarker(
                            now: context.date,
                            columns: columnsCount,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            spacing: cellSpacing,
                            tint: Theme.neonCyan,
                            canvasWidth: canvasWidth,
                            gridOriginX: gridOriginX
                        )
                    }
                    .frame(width: canvasWidth, height: gridHeight, alignment: .topLeading)
                }

                if showsAxisMarkers {
                    HStack {
                        Text("x00")
                        Spacer()
                        Text("x95")
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.24))
                    .padding(.horizontal, 4)
                    .frame(width: canvasWidth, height: gridHeight, alignment: .center)
                }
            }
            .frame(width: canvasWidth, height: gridHeight, alignment: .topLeading)

            if showsAxisMarkers {
                Text("☾")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))
                    .frame(width: canvasWidth, alignment: .center)
            }
        }
    }
}

private struct CalendarHighlighterOverlay: View {
    let bins: [DayBin]
    let arcs: [CalendarArcSegment]
    let columnsCount: Int
    let rowsCount: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let spacing: CGFloat
    let gridWidth: CGFloat
    let gridHeight: CGFloat
    let gridOriginX: CGFloat
    var onHoverChanged: ((CalendarArcSegment?, CGPoint?) -> Void)? = nil
    var onArcTapped: ((CalendarArcSegment?, CGPoint?) -> Void)? = nil
    var onBinHoverChanged: ((DayBin?, CGPoint?) -> Void)? = nil

    @State private var hoveredArcID: UUID?
    @State private var lastHoverAnchor: CGPoint?
    @State private var lastBinIndex: Int?
    @State private var lastBinAnchor: CGPoint?
    @State private var cachedFragments: [HighlightFragment] = []

    private struct HighlightFragment {
        let arc: CalendarArcSegment
        let rect: CGRect
        let color: Color
        let isAllDayLike: Bool
    }

    private func makeFragments() -> [HighlightFragment] {
        var output: [HighlightFragment] = []
        output.reserveCapacity(arcs.count * rowsCount)

        let totalBins = TimelineGeometry.totalBins
        let rowBinCount = columnsCount

        for arc in arcs {
            let startRaw = Int(floor(arc.startRatio * Double(totalBins)))
            let endExclusiveRaw = Int(ceil(arc.endRatio * Double(totalBins)))
            let startBin = max(0, min(totalBins - 1, startRaw))
            let endExclusive = max(startBin + 1, min(totalBins, endExclusiveRaw))
            let endBin = endExclusive - 1
            let coveredBins = endExclusive - startBin
            let allDayLike = coveredBins >= (totalBins - 2)
            let color = highlightColor(for: arc)

            if allDayLike {
                output.append(
                    HighlightFragment(
                        arc: arc,
                        rect: CGRect(x: gridOriginX, y: 0, width: gridWidth, height: gridHeight).insetBy(dx: -1.2, dy: -1.2),
                        color: color,
                        isAllDayLike: true
                    )
                )
                continue
            }

            for rowIndex in 0 ..< rowsCount {
                let rowStart = rowIndex * rowBinCount
                let rowEnd = rowStart + rowBinCount - 1
                let segmentStart = max(startBin, rowStart)
                let segmentEnd = min(endBin, rowEnd)
                guard segmentStart <= segmentEnd else { continue }

                let columnStart = segmentStart - rowStart
                let columnEnd = segmentEnd - rowStart
                let x = gridOriginX + CGFloat(columnStart) * (cellWidth + spacing)
                let y = CGFloat(rowIndex) * (cellHeight + spacing)
                let columnsCovered = columnEnd - columnStart + 1
                let width = CGFloat(columnsCovered) * cellWidth + CGFloat(max(0, columnsCovered - 1)) * spacing
                let baseRect = CGRect(x: x, y: y, width: width, height: cellHeight)

                // Small row-based expansion keeps overlapped events all visible.
                let expansion = 0.8 + CGFloat(min(arc.row, 5)) * 0.35
                output.append(
                    HighlightFragment(
                        arc: arc,
                        rect: baseRect.insetBy(dx: -expansion, dy: -expansion),
                        color: color,
                        isAllDayLike: false
                    )
                )
            }
        }

        return output
    }

    var body: some View {
        GeometryReader { _ in
            Canvas { context, _ in
                for fragment in cachedFragments {
                    let hovered = fragment.arc.id == hoveredArcID
                    let baseColor = fragment.color
                    let lineWidth: CGFloat = fragment.isAllDayLike ? (hovered ? 1.5 : 0.95) : (hovered ? 2.0 : 1.1)
                    let glowWidth: CGFloat = fragment.isAllDayLike ? (hovered ? 2.2 : 1.35) : (hovered ? 3.2 : 1.9)
                    let cornerRadius = max(3, fragment.rect.height * (fragment.isAllDayLike ? 0.08 : 0.23))
                    let path = Path(roundedRect: fragment.rect, cornerRadius: cornerRadius)
                    let glowPath = Path(roundedRect: fragment.rect.insetBy(dx: -0.7, dy: -0.7), cornerRadius: cornerRadius + 0.5)
                    let dashPhase = CGFloat(abs(fragment.arc.id.hashValue % 13))
                    let dash: [CGFloat] = fragment.isAllDayLike ? [10, 5] : [6.4, 2.8]

                    context.stroke(
                        glowPath,
                        with: .color(baseColor.opacity(hovered ? 0.22 : 0.11)),
                        style: StrokeStyle(lineWidth: glowWidth, lineCap: .round, lineJoin: .round)
                    )
                    if hovered && !fragment.isAllDayLike {
                        context.fill(
                            path,
                            with: .color(baseColor.opacity(0.07))
                        )
                    }
                    context.stroke(
                        path,
                        with: .color(baseColor.opacity(hovered ? 0.9 : 0.52)),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: dash,
                            dashPhase: dashPhase
                        )
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let hit = hitFragment(at: location)
                    if let hit {
                        let anchor = CGPoint(x: hit.rect.midX, y: hit.rect.minY)
                        let isNewArc = hoveredArcID != hit.arc.id
                        let movedEnough = lastHoverAnchor.map { distance($0, anchor) > 8 } ?? true
                        hoveredArcID = hit.arc.id
                        if isNewArc || movedEnough {
                            lastHoverAnchor = anchor
                            onHoverChanged?(hit.arc, anchor)
                        }
                        if lastBinIndex != nil {
                            lastBinIndex = nil
                            lastBinAnchor = nil
                            onBinHoverChanged?(nil, nil)
                        }
                    } else if hoveredArcID != nil {
                        hoveredArcID = nil
                        lastHoverAnchor = nil
                        onHoverChanged?(nil, nil)
                    } else if let binHit = hitBin(at: location) {
                        let indexChanged = lastBinIndex != binHit.bin.index0to95
                        let movedEnough = lastBinAnchor.map { distance($0, binHit.anchor) > 8 } ?? true
                        if indexChanged || movedEnough {
                            lastBinIndex = binHit.bin.index0to95
                            lastBinAnchor = binHit.anchor
                            onBinHoverChanged?(binHit.bin, binHit.anchor)
                        }
                    } else if lastBinIndex != nil {
                        lastBinIndex = nil
                        lastBinAnchor = nil
                        onBinHoverChanged?(nil, nil)
                    }
                case .ended:
                    hoveredArcID = nil
                    lastHoverAnchor = nil
                    lastBinIndex = nil
                    lastBinAnchor = nil
                    onHoverChanged?(nil, nil)
                    onBinHoverChanged?(nil, nil)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let hit = hitFragment(at: value.location)
                        if let hit {
                            hoveredArcID = hit.arc.id
                            let anchor = CGPoint(x: hit.rect.midX, y: hit.rect.minY)
                            lastHoverAnchor = anchor
                            onArcTapped?(hit.arc, anchor)
                        } else {
                            hoveredArcID = nil
                            lastHoverAnchor = nil
                            onArcTapped?(nil, nil)
                        }
                    }
            )
            .onAppear {
                cachedFragments = makeFragments()
            }
            .onChange(of: arcs) { _, _ in
                cachedFragments = makeFragments()
                hoveredArcID = nil
                lastHoverAnchor = nil
                lastBinIndex = nil
                lastBinAnchor = nil
            }
        }
        .allowsHitTesting(!bins.isEmpty)
    }

    private func hitFragment(at point: CGPoint) -> HighlightFragment? {
        for fragment in cachedFragments.reversed() {
            if fragment.rect.insetBy(dx: -3.5, dy: -3.5).contains(point) {
                return fragment
            }
        }
        return nil
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func hitBin(at point: CGPoint) -> (bin: DayBin, anchor: CGPoint)? {
        let stepX = cellWidth + spacing
        let stepY = cellHeight + spacing
        let localX = point.x - gridOriginX
        let localY = point.y
        guard localX >= 0, localY >= 0, localX <= gridWidth, localY <= gridHeight else { return nil }

        let column = Int(localX / stepX)
        let row = Int(localY / stepY)
        guard column >= 0, column < columnsCount, row >= 0, row < rowsCount else { return nil }

        let inCellX = localX - CGFloat(column) * stepX
        let inCellY = localY - CGFloat(row) * stepY
        guard inCellX <= cellWidth, inCellY <= cellHeight else { return nil }

        let index = row * columnsCount + column
        guard bins.indices.contains(index) else { return nil }

        let anchor = CGPoint(
            x: gridOriginX + CGFloat(column) * stepX + cellWidth / 2,
            y: CGFloat(row) * stepY + cellHeight / 2
        )
        return (bins[index], anchor)
    }

    private func highlightColor(for arc: CalendarArcSegment) -> Color {
        if isBlueLike(hex: arc.colorHex) || isRedLike(hex: arc.colorHex) {
            let fallbackPalette = [
                Color(hex: "#FFD45E"),
                Color(hex: "#B7FF63"),
                Color(hex: "#FFB974"),
                Color(hex: "#D88FFF"),
                Color(hex: "#7AFFC8"),
                Color(hex: "#FFC8DE"),
            ]
            let index = abs((arc.sourceName + arc.eventTitle + arc.colorHex).hashValue) % fallbackPalette.count
            return fallbackPalette[index]
        }
        return Color(hex: arc.colorHex)
    }

    private func isBlueLike(hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return (blue > red * 1.08 && green > red * 0.72) || (blue > 0.54 && green > 0.52 && red < 0.45)
    }

    private func isRedLike(hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return red > 0.62 && green < 0.45 && blue < 0.45
    }
}

private struct QueryHighlightOverlay: View {
    let bins: [DayBin]
    let highlightedRanges: [DateInterval]
    let columnsCount: Int
    let rowsCount: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let spacing: CGFloat
    let gridOriginX: CGFloat

    @State private var pulse = false

    var body: some View {
        Canvas { context, _ in
            let matchingIndices = matchingBinIndices()
            let stepX = cellWidth + spacing
            let stepY = cellHeight + spacing
            let opacity = pulse ? 0.28 : 0.12

            for index in matchingIndices {
                let column = index % columnsCount
                let row = index / columnsCount
                let x = gridOriginX + CGFloat(column) * stepX - 1.2
                let y = CGFloat(row) * stepY - 1.2
                let rect = CGRect(x: x, y: y, width: cellWidth + 2.4, height: cellHeight + 2.4)
                let cornerRadius = max(2, cellWidth * 0.35)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                context.stroke(
                    path,
                    with: .color(Theme.neonCyan.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func matchingBinIndices() -> Set<Int> {
        var indices = Set<Int>()
        for range in highlightedRanges {
            for (i, bin) in bins.enumerated() {
                let binInterval = DateInterval(start: bin.startAt, end: bin.endAt)
                if binInterval.intersects(range) {
                    indices.insert(i)
                }
            }
        }
        return indices
    }
}
