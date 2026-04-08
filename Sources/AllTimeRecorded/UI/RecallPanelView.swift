import SwiftUI

struct RecallPanelView: View {
    @ObservedObject var viewModel: RecallPanelViewModel
    var onClose: () -> Void

    @State private var cursorVisible = true
    @FocusState private var inputFocused: Bool

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

            scanlineOverlay
            ASCIIBackgroundView(transcriptsRoot: AppPaths().transcriptsRoot)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Divider().background(Theme.neonCyan.opacity(0.15))
                resultArea
                promptArea
            }
            .padding(12)
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
            inputFocused = true
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("R E C A L L")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.neonCyan.opacity(0.7))
                .tracking(2)

            Spacer()

            Button(action: onClose) {
                Text("\u{00D7}")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.bottom, 8)
    }

    // MARK: - Results Area

    private var resultArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    switch viewModel.state {
                    case .idle:
                        idleHint
                    case .searching:
                        searchingIndicator
                    case .results(let groups, let total):
                        resultsContent(groups: groups, total: total)
                    case .noResults:
                        noResultsHint
                    case .error(let message):
                        errorHint(message)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var idleHint: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 40)
            Text("query your recorded transcripts")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
            Text("type below and press enter")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.18))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var searchingIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("searching...")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.neonCyan.opacity(0.6))
            progressBar
        }
    }

    @State private var progressPhase: CGFloat = 0

    private var progressBar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let barWidth = totalWidth * 0.35
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.neonCyan.opacity(0.5))
                .frame(width: barWidth, height: 3)
                .offset(x: progressPhase * (totalWidth - barWidth))
        }
        .frame(height: 3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                progressPhase = 1
            }
        }
    }

    private func resultsContent(groups: [QueryResultGroup], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                dayCard(group: group)
            }

            summaryLine(total: total, days: groups.count)
        }
    }

    private func dayCard(group: QueryResultGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(group.day)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan.opacity(0.45))
                Rectangle()
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            ForEach(group.results) { result in
                resultRow(result: result)
            }

            Spacer().frame(height: 4)
        }
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.neonCyan.opacity(0.12), lineWidth: 0.6)
        )
    }

    private func resultRow(result: QueryResult) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(result.timeLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.neonCyan.opacity(0.65))
                .frame(width: 38, alignment: .trailing)

            Text(result.text)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            viewModel.hoveredResultID == result.id
                ? Theme.neonCyan.opacity(0.08)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .onHover { hovering in
            viewModel.hoverResult(hovering ? result : nil)
        }
        .onTapGesture {
            viewModel.hoverResult(result)
        }
    }

    private func summaryLine(total: Int, days: Int) -> some View {
        HStack(spacing: 0) {
            dashLine
            Text(" \(total) results across \(viewModel.dayCountLabel) ")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
            dashLine
        }
        .frame(maxWidth: .infinity)
    }

    private var dashLine: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    private var noResultsHint: some View {
        Text("no matches found")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    private func errorHint(_ message: String) -> some View {
        Text("error: \(message)")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.lowDiskRed.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    // MARK: - Prompt

    private var promptArea: some View {
        HStack(spacing: 6) {
            Text("\u{25B6}")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.neonCyan.opacity(cursorVisible ? 0.9 : 0.4))

            TextField("", text: $viewModel.queryText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit {
                    viewModel.submit()
                }

            if !viewModel.queryText.isEmpty {
                Button(action: { viewModel.clear() }) {
                    Text("CLR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.neonCyan.opacity(0.18), lineWidth: 0.6)
        )
    }

    // MARK: - Scanline Effect

    private var scanlineOverlay: some View {
        Canvas { context, size in
            let spacing: CGFloat = 2
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: 0.5)
                context.fill(Path(rect), with: .color(.white.opacity(0.012)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ASCII Background Animation

private struct ASCIIBackgroundView: View {
    let transcriptsRoot: URL

    private let cols = 30
    private let rows = 24
    private let cellW: CGFloat = 9.6
    private let cellH: CGFloat = 13

    @State private var cells: [CellState] = []
    @State private var words: [String] = []
    @State private var ripples: [Ripple] = []
    @State private var tick: UInt64 = 0
    @State private var timer: Timer?

    private struct CellState {
        var char: Character = " "
        var brightness: Double = 0
    }

    private struct Ripple {
        let centerCol: Int
        let centerRow: Int
        let word: String
        let bornTick: UInt64
        let charOffset: Int  // where in the grid the word starts
    }

    var body: some View {
        Canvas { context, size in
            guard !cells.isEmpty else { return }
            for row in 0..<rows {
                for col in 0..<cols {
                    let idx = row * cols + col
                    guard idx < cells.count else { continue }
                    let cell = cells[idx]
                    guard cell.brightness > 0.005 else { continue }
                    let x = CGFloat(col) * cellW + 4
                    let y = CGFloat(row) * cellH + 24
                    guard x < size.width, y < size.height else { continue }
                    let text = Text(String(cell.char))
                        .font(.system(size: 8.5, weight: .light, design: .monospaced))
                        .foregroundColor(Theme.neonCyan.opacity(cell.brightness))
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
                }
            }
        }
        .onAppear {
            cells = Array(repeating: CellState(), count: cols * rows)
            loadWords()
            timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                step()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func loadWords() {
        var collected: [String] = []
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: transcriptsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            words = []
            return
        }
        for dir in dirs.shuffled().prefix(8) {
            let jsonURL = dir.appendingPathComponent("day-transcript.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let segments: [[String: Any]]
            if let t = obj["transcription"] as? [[String: Any]] {
                segments = t
            } else if let s = obj["segments"] as? [[String: Any]] {
                segments = s
            } else { continue }

            for seg in segments.prefix(40) {
                if let text = seg["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 3 {
                        // Split into fragments of 8-20 chars
                        let fragment = String(trimmed.prefix(Int.random(in: 8...20)))
                        collected.append(fragment)
                    }
                }
            }
        }
        words = collected.isEmpty ? [] : collected.shuffled()
    }

    private func step() {
        guard !cells.isEmpty else { return }
        tick += 1

        // Decay all cells
        for i in cells.indices {
            cells[i].brightness *= 0.88
            if cells[i].brightness < 0.005 {
                cells[i].brightness = 0
                cells[i].char = " "
            }
        }

        // Spawn new ripple every ~18 ticks if we have words
        if !words.isEmpty, tick % UInt64.random(in: 14...22) == 0 {
            let word = words[Int.random(in: 0..<words.count)]
            let centerCol = Int.random(in: 2..<(cols - 2))
            let centerRow = Int.random(in: 2..<(rows - 2))
            let charOffset = centerRow * cols + max(0, centerCol - word.count / 2)
            ripples.append(Ripple(
                centerCol: centerCol,
                centerRow: centerRow,
                word: word,
                bornTick: tick,
                charOffset: charOffset
            ))
        }

        // Process ripples
        var alive: [Ripple] = []
        for ripple in ripples {
            let age = Int(tick - ripple.bornTick)
            let maxAge = 28
            guard age < maxAge else { continue }
            alive.append(ripple)

            let radius = Double(age) * 0.8
            let peakBrightness = 0.06 * (1.0 - Double(age) / Double(maxAge))

            // Paint word chars at center
            if age < 18 {
                let wordChars = Array(ripple.word)
                for (i, ch) in wordChars.enumerated() {
                    let idx = ripple.charOffset + i
                    guard idx >= 0, idx < cells.count else { continue }
                    let wordBrightness = peakBrightness * 1.8
                    if wordBrightness > cells[idx].brightness {
                        cells[idx].char = ch
                        cells[idx].brightness = wordBrightness
                    }
                }
            }

            // Ripple ring
            for row in 0..<rows {
                for col in 0..<cols {
                    let dx = Double(col - ripple.centerCol)
                    let dy = Double(row - ripple.centerRow) * 1.6
                    let dist = (dx * dx + dy * dy).squareRoot()
                    let ringDelta = abs(dist - radius)
                    guard ringDelta < 1.8 else { continue }
                    let falloff = 1.0 - ringDelta / 1.8
                    let b = peakBrightness * falloff * 0.5
                    let idx = row * cols + col
                    guard idx < cells.count else { continue }
                    if b > cells[idx].brightness {
                        cells[idx].brightness = b
                        if cells[idx].char == " " {
                            cells[idx].char = "·"
                        }
                    }
                }
            }
        }
        ripples = alive
    }
}
