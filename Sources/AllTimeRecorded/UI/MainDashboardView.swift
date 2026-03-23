import AppKit
import CoreGraphics
import IOKit.ps
import SwiftUI

struct MainDashboardView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var calendarService: CalendarOverlayService
    @ObservedObject var modelAssetService: ModelAssetService
    var showsWindowControls: Bool = false
    var onCloseWindow: (() -> Void)? = nil
    var onMinimizeWindow: (() -> Void)? = nil
    var onZoomWindow: (() -> Void)? = nil

    @State private var pulse = false
    @State private var hoveredArc: CalendarArcSegment?
    @State private var hoverLocation: CGPoint?
    @State private var hoveredBin: DayBin?
    @State private var hoveredBinLocation: CGPoint?
    @State private var pinnedArc: CalendarArcSegment?
    @State private var pinnedLocation: CGPoint?
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showingDatePicker = false
    @State private var timelinePanelSize: CGSize = .zero
    @State private var showingCalendarManager = false
    @State private var isPreparingModel = false
    @State private var isInstallingCLI = false
    @State private var statusHint: String?
    @State private var transcriptionHealth = "Transcribe: checking..."
    @State private var calendarReloadTask: Task<Void, Never>?
    @StateObject private var historyStore = TimelineHistoryStore()

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

            VStack(alignment: .leading, spacing: 12) {
                header
                dayNavigator
                timeline
                modelControls
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
            historyStore.reload()
            modelAssetService.refreshStateFromDisk()
            refreshTranscriptionHealth()
            scheduleCalendarReload(for: selectedDay, delayNanoseconds: 0)
        }
        .onChange(of: selectedDay) { _, newValue in
            let normalized = Calendar.current.startOfDay(for: newValue)
            if normalized != newValue {
                selectedDay = normalized
                return
            }
            hoveredArc = nil
            hoverLocation = nil
            hoveredBin = nil
            hoveredBinLocation = nil
            pinnedArc = nil
            pinnedLocation = nil
            scheduleCalendarReload(for: normalized)
        }
        .onDisappear {
            calendarReloadTask?.cancel()
            calendarReloadTask = nil
        }
        .sheet(isPresented: $showingCalendarManager) {
            CalendarSourcesSheet(service: calendarService)
                .frame(width: 420, height: 400)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if showsWindowControls {
                    windowControls
                }
                Text("AllTimeRecorded")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text("Open-lid audio, local text pickup")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()

            iconButton(systemName: "calendar.badge.plus", help: "Calendar Sources") {
                showingCalendarManager = true
            }
            iconButton(systemName: "folder", help: "Open Recording Folder") {
                openRecordingFolder()
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor.opacity(pulse && appModel.snapshot.state == .recording ? 1 : 0.55))
                    .frame(width: 8, height: 8)
                Text(appModel.stateTitle)
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

    private var windowControls: some View {
        HStack(spacing: 8) {
            windowControlDot(
                color: Color(red: 1.0, green: 0.37, blue: 0.33),
                help: "Close",
                action: onCloseWindow
            )
            windowControlDot(
                color: Color(red: 1.0, green: 0.78, blue: 0.12),
                help: "Minimize",
                action: onMinimizeWindow
            )
            windowControlDot(
                color: Color(red: 0.19, green: 0.83, blue: 0.35),
                help: "Zoom",
                action: onZoomWindow
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
    }

    private func windowControlDot(
        color: Color,
        help: String,
        action: (() -> Void)?
    ) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle()
                    .fill(color.opacity(action == nil ? 0.45 : 0.95))
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 4, height: 4)
                    .offset(x: -1, y: -1)
                    .blendMode(.plusLighter)
            }
            .frame(width: 11, height: 11)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .help(help)
    }

    private var dayNavigator: some View {
        HStack(spacing: 7) {
            tinyRoundButton(icon: "chevron.left") {
                shiftDay(by: -1)
            }

            Button(action: { showingDatePicker.toggle() }) {
                Text(selectedDayLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.16), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePicker, arrowEdge: .top) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { selectedDay },
                        set: { selectedDay = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(10)
                .frame(width: 250)
            }

            tinyRoundButton(icon: "chevron.right") {
                shiftDay(by: 1)
            }

            if !isSelectedDayToday {
                Button("Today") {
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.neonCyan.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Theme.neonCyan.opacity(0.28), lineWidth: 0.8)
                )
            }

            Spacer()
        }
    }

    private var timeline: some View {
        HStack {
            Spacer(minLength: 0)
            TimelineHeatmapPanel(
                bins: displayBins,
                state: displayState,
                arcs: calendarService.currentArcs,
                onHoverChanged: { arc, point in
                    if pinnedArc == nil {
                        hoveredArc = arc
                        hoverLocation = point
                        if arc != nil {
                            hoveredBin = nil
                            hoveredBinLocation = nil
                        }
                    }
                },
                onArcTapped: { arc, point in
                    if let arc, let point {
                        if pinnedArc?.id == arc.id {
                            pinnedArc = nil
                            pinnedLocation = nil
                        } else {
                            pinnedArc = arc
                            pinnedLocation = point
                        }
                        hoveredBin = nil
                        hoveredBinLocation = nil
                        openTranscriptForDayFromEvent(arc: arc)
                    } else {
                        pinnedArc = nil
                        pinnedLocation = nil
                    }
                },
                onBinHoverChanged: { bin, point in
                    guard pinnedArc == nil, hoveredArc == nil else { return }
                    hoveredBin = bin
                    hoveredBinLocation = point
                },
                cellWidth: 6,
                cellHeight: 24,
                cellSpacing: 1.4,
                horizontalPadding: 94,
                showsAxisMarkers: true,
                showsNowMarker: isSelectedDayToday
            )
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: TimelinePanelSizePreferenceKey.self, value: proxy.size)
                }
            )
            .overlay(alignment: .topLeading) {
                if let displayArc = pinnedArc ?? hoveredArc,
                   let displayLocation = pinnedLocation ?? hoverLocation {
                    CalendarEventHoverCard(arc: displayArc)
                        .offset(
                            x: hoverCardX(anchorX: displayLocation.x, panelWidth: timelinePanelSize.width),
                            y: hoverCardY(anchorY: displayLocation.y, panelHeight: timelinePanelSize.height)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else if let hoveredBin,
                          let hoveredBinLocation {
                    TimelineBinHoverCard(bin: hoveredBin, bins: displayBins)
                        .offset(
                            x: hoverCardX(anchorX: hoveredBinLocation.x, panelWidth: timelinePanelSize.width, cardWidth: 148),
                            y: hoverCardY(anchorY: hoveredBinLocation.y, panelHeight: timelinePanelSize.height, cardHeight: 66)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .onPreferenceChange(TimelinePanelSizePreferenceKey.self) { newValue in
                timelinePanelSize = newValue
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 154)
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusPill(title: "Model", value: modelStatusText, tint: modelStatusColor)
                Spacer()
                if let statusHint {
                    Text(statusHint)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                } else if !transcriptionHealth.isEmpty {
                    Text(transcriptionHealth)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                } else if case .downloading = modelAssetService.state {
                    Text("Large-v3-turbo downloading in background")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                } else if case .failed(let message) = modelAssetService.state {
                    Text(message)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.lowDiskRed.opacity(0.9))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                actionButton(
                    icon: modelActionIcon,
                    title: modelActionTitle,
                    tint: modelStatusColor,
                    disabled: isModelBusy
                ) {
                    prepareModel()
                }
                actionButton(icon: "cpu", title: "Model Folder", tint: .white, disabled: false) {
                    openModelFolder()
                }
                actionButton(icon: "text.bubble", title: "Transcript Folder", tint: .white, disabled: false) {
                    openTranscriptFolder()
                }
                actionButton(icon: "waveform", title: "Audio Folder", tint: .white, disabled: false) {
                    openRecordingFolder()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func actionButton(
        icon: String,
        title: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(disabled ? Color.white.opacity(0.45) : tint.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func statusPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.16), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var isModelBusy: Bool {
        if isPreparingModel {
            return true
        }
        if isInstallingCLI {
            return true
        }
        switch modelAssetService.state {
        case .downloading, .verifying:
            return true
        default:
            return false
        }
    }

    private var modelActionTitle: String {
        if case .ready = modelAssetService.state, resolveWhisperCLIPath() == nil {
            return isInstallingCLI ? "Installing CLI..." : "Install CLI"
        }
        switch modelAssetService.state {
        case .idle:
            return "Prepare Model"
        case .downloading:
            return "Downloading..."
        case .verifying:
            return "Verifying..."
        case .ready:
            return "Re-Verify Model"
        case .failed:
            return "Retry Download"
        }
    }

    private var modelActionIcon: String {
        if case .ready = modelAssetService.state, resolveWhisperCLIPath() == nil {
            return "terminal"
        }
        switch modelAssetService.state {
        case .ready:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        default:
            return "arrow.down.circle"
        }
    }

    private var modelStatusText: String {
        switch modelAssetService.state {
        case .idle:
            return "Not Ready"
        case .downloading:
            return "Downloading"
        case .verifying:
            return "Verifying"
        case .ready:
            if let bytes = modelAssetService.modelFileSizeBytes {
                return "Ready \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            }
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    private var modelStatusColor: Color {
        switch modelAssetService.state {
        case .ready:
            return Theme.neonCyan
        case .failed:
            return Theme.lowDiskRed
        case .downloading, .verifying:
            return Theme.gapAmber
        default:
            return .white
        }
    }

    private var stateColor: Color {
        switch appModel.snapshot.state {
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

    private var displayBins: [DayBin] {
        if isSelectedDayToday {
            return appModel.snapshot.bins
        }
        return historyStore.bins(for: selectedDay)
    }

    private var displayState: RecorderState {
        isSelectedDayToday ? appModel.snapshot.state : .recording
    }

    private var isSelectedDayToday: Bool {
        Calendar.current.isDate(selectedDay, inSameDayAs: Date())
    }

    private var selectedDayLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDay).uppercased()
    }

    private func tinyRoundButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                )
        }
        .buttonStyle(.plain)
    }

    private func shiftDay(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectedDay = Calendar.current.startOfDay(for: newDate)
    }

    private func hoverCardX(anchorX: CGFloat, panelWidth: CGFloat, cardWidth: CGFloat = 164) -> CGFloat {
        let margin: CGFloat = 6
        let rightX = anchorX + 10
        let maxX = max(margin, panelWidth - cardWidth - margin)
        if rightX <= maxX {
            return max(margin, rightX)
        }
        return max(margin, min(maxX, anchorX - cardWidth - 10))
    }

    private func hoverCardY(anchorY: CGFloat, panelHeight: CGFloat, cardHeight: CGFloat = 74) -> CGFloat {
        let margin: CGFloat = 4
        let preferred = anchorY - cardHeight - 8
        let maxY = max(margin, panelHeight - cardHeight - margin)
        return max(margin, min(maxY, preferred))
    }

    private func prepareModel() {
        guard !isModelBusy else { return }
        if case .ready = modelAssetService.state, resolveWhisperCLIPath() == nil {
            installWhisperCLI()
            return
        }
        isPreparingModel = true
        let wasReady = modelAssetService.isLocalModelUsable
        Task { @MainActor in
            await modelAssetService.ensureModelReady()
            isPreparingModel = false
            modelAssetService.refreshStateFromDisk()
            refreshTranscriptionHealth()

            switch modelAssetService.state {
            case .ready:
                if let size = modelAssetService.modelFileSizeBytes {
                    pushHint("Model ready · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                } else {
                    pushHint("Model ready")
                }
                if resolveWhisperCLIPath() == nil {
                    pushHint("Model ready; install whisper-cli for transcription")
                }
                if wasReady {
                    openModelFolder()
                }
            case .failed(let message):
                pushHint(message)
            default:
                break
            }
        }
    }

    private func openRecordingFolder() {
        let paths = AppPaths()
        openDirectory(paths.audioRoot, label: "Audio")
    }

    private func openModelFolder() {
        let paths = AppPaths()
        openDirectory(paths.modelsRoot, label: "Model")
    }

    private func openTranscriptFolder() {
        let paths = AppPaths()
        openDirectory(paths.transcriptsRoot, label: "Transcript")
        refreshTranscriptionHealth()
    }

    private func openTranscriptForDayFromEvent(arc: CalendarArcSegment) {
        let paths = AppPaths()
        try? paths.ensureBaseDirectories()
        let day = Calendar.current.startOfDay(for: arc.startAt)
        let dayFolder = paths.transcriptsRoot.appendingPathComponent(dayFolderName(for: day), isDirectory: true)
        let txtURL = dayFolder.appendingPathComponent("day-transcript.txt", isDirectory: false)
        let jsonURL = dayFolder.appendingPathComponent("day-transcript.json", isDirectory: false)

        if FileManager.default.fileExists(atPath: txtURL.path) {
            NSWorkspace.shared.open(txtURL)
            pushHint("Opened transcript text for \(dayFolder.lastPathComponent)")
            return
        }
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            NSWorkspace.shared.open(jsonURL)
            pushHint("Opened transcript json for \(dayFolder.lastPathComponent)")
            return
        }

        NSWorkspace.shared.open(paths.transcriptsRoot)
        pushHint("No transcript file yet for \(dayFolder.lastPathComponent)")
    }

    private func dayFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func pushHint(_ text: String) {
        statusHint = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if statusHint == text {
                statusHint = nil
            }
        }
    }

    private func refreshTranscriptionHealth() {
        if !modelAssetService.isLocalModelUsable {
            transcriptionHealth = "Transcribe: model not ready"
            return
        }

        guard let cliPath = resolveWhisperCLIPath() else {
            transcriptionHealth = "Transcribe: whisper-cli missing (brew install whisper-cpp)"
            return
        }

        let pending = pendingTranscriptDaysCount()
        if pending == 0 {
            if hasAudioOnlyForTodayWithoutTranscript() {
                transcriptionHealth = "Transcribe: waiting day end"
            } else {
                transcriptionHealth = "Transcribe: no pending day"
            }
            return
        }
        if !isOnACPower() {
            transcriptionHealth = "Transcribe: \(pending)d pending (waiting AC power)"
            return
        }
        if !isUserIdle() {
            transcriptionHealth = "Transcribe: \(pending)d pending (waiting idle)"
        } else {
            let cliName = URL(fileURLWithPath: cliPath).lastPathComponent
            transcriptionHealth = "Transcribe: \(pending)d pending (AC+idle · \(cliName))"
        }
    }

    private func resolveWhisperCLIPath() -> String? {
        let paths = AppPaths()
        let candidates = [
            paths.modelsRoot.appendingPathComponent("whisper-cli", isDirectory: false).path,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/usr/bin/whisper-cli",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func pendingTranscriptDaysCount() -> Int {
        let paths = AppPaths()
        let fm = FileManager.default
        guard let dayDirs = try? fm.contentsOfDirectory(
            at: paths.audioRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        let today = Calendar.current.startOfDay(for: Date())
        return dayDirs.filter { dir in
            guard ((try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) else { return false }
            guard let day = parseDayFolderName(dir.lastPathComponent), day < today else { return false }
            let transcriptJSON = paths.transcriptsRoot
                .appendingPathComponent(dir.lastPathComponent, isDirectory: true)
                .appendingPathComponent("day-transcript.json", isDirectory: false)
            return !fm.fileExists(atPath: transcriptJSON.path)
        }.count
    }

    private func parseDayFolderName(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func openDirectory(_ url: URL, label: String) {
        let paths = AppPaths()
        do {
            try paths.ensureBaseDirectories()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            pushHint("\(label) folder create failed")
            return
        }

        if NSWorkspace.shared.open(url) {
            pushHint("Opened \(label) folder")
            return
        }

        let revealed = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        if revealed {
            pushHint("Opened \(label) folder")
        } else {
            pushHint("Cannot open \(label) folder")
        }
    }

    private func resolveBrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func installWhisperCLI() {
        guard !isInstallingCLI else { return }
        guard let brewPath = resolveBrewPath() else {
            pushHint("Homebrew missing · run brew install whisper-cpp")
            refreshTranscriptionHealth()
            return
        }
        isInstallingCLI = true
        pushHint("Installing whisper-cpp...")

        Task { @MainActor in
            let status = await Task.detached(priority: .utility) { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = ["install", "whisper-cpp"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return -1
                }
            }.value

            isInstallingCLI = false
            refreshTranscriptionHealth()
            if status == 0, resolveWhisperCLIPath() != nil {
                pushHint("whisper-cli installed")
            } else {
                pushHint("CLI install failed · brew install whisper-cpp")
            }
        }
    }

    private func scheduleCalendarReload(for day: Date, delayNanoseconds: UInt64 = 140_000_000) {
        calendarReloadTask?.cancel()
        calendarReloadTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await calendarService.reload(for: day)
        }
    }

    private func hasAudioOnlyForTodayWithoutTranscript() -> Bool {
        let paths = AppPaths()
        let fm = FileManager.default
        let todayFolder = dayFolderName(for: Date())
        let audioToday = paths.audioRoot.appendingPathComponent(todayFolder, isDirectory: true)
        guard (try? audioToday.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        let transcriptJSON = paths.transcriptsRoot
            .appendingPathComponent(todayFolder, isDirectory: true)
            .appendingPathComponent("day-transcript.json", isDirectory: false)
        return !fm.fileExists(atPath: transcriptJSON.path)
    }

    private func isOnACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String else {
                continue
            }
            if state == kIOPSACPowerValue {
                return true
            }
        }
        return false
    }

    private func isUserIdle() -> Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        return seconds >= AppConstants.transcriptionIdleSecondsThreshold
    }
}

private struct TimelinePanelSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TimelineBinHoverCard: View {
    let bin: DayBin
    let bins: [DayBin]

    private var timeRangeText: String {
        let span = contiguousSpan
        return "\(formatTime(span.startAt))-\(formatTime(span.endAt))"
    }

    private var detailText: String {
        switch bin.status {
        case .recorded:
            return "recorded window · \(spanDurationLabel)"
        case .gap:
            return "interruption window · \(spanDurationLabel)"
        case .none:
            return "quiet window · \(spanDurationLabel)"
        }
    }

    private var contiguousSpan: (startAt: Date, endAt: Date) {
        guard bins.indices.contains(bin.index0to95) else {
            return (bin.startAt, bin.endAt)
        }
        var lower = bin.index0to95
        var upper = bin.index0to95
        while lower > 0, bins[lower - 1].status == bin.status {
            lower -= 1
        }
        while upper + 1 < bins.count, bins[upper + 1].status == bin.status {
            upper += 1
        }
        return (bins[lower].startAt, bins[upper].endAt)
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: bins.first?.startAt ?? bin.startAt)
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
    }

    private func formatTime(_ value: Date) -> String {
        // Render day-end as 24:00 to avoid confusing 01:45-00:00 style labels.
        if abs(value.timeIntervalSince(dayEnd)) < 1 {
            return "24:00"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }

    private var spanDurationLabel: String {
        let duration = max(0, Int(contiguousSpan.endAt.timeIntervalSince(contiguousSpan.startAt)))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm", max(1, minutes))
    }

    private var statusText: String {
        switch bin.status {
        case .recorded:
            return "Recorded"
        case .gap:
            return "Gap"
        case .none:
            return "Idle"
        }
    }

    private var accent: Color {
        switch bin.status {
        case .recorded:
            return Theme.neonCyan
        case .gap:
            return Theme.gapAmber
        case .none:
            return .white.opacity(0.75)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeRangeText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
            Text(statusText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
            Text(detailText)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 148, alignment: .leading)
        .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

@MainActor
private final class TimelineHistoryStore: ObservableObject {
    private let eventStore: EventStore?
    private var segments: [RecordingSegment] = []
    private var gaps: [GapEvent] = []
    private var loudness: [LoudnessEvent] = []
    private var cacheByDay: [String: [DayBin]] = [:]

    init() {
        eventStore = try? EventStore(paths: AppPaths())
    }

    func reload() {
        guard let eventStore else {
            segments = []
            gaps = []
            loudness = []
            return
        }
        let loaded = eventStore.loadTimelineData()
        segments = loaded.segments
        gaps = loaded.gaps
        loudness = loaded.loudness
        cacheByDay.removeAll(keepingCapacity: true)
    }

    func bins(for day: Date) -> [DayBin] {
        let key = dayKey(day)
        if let cached = cacheByDay[key] {
            return cached
        }
        let mapped = DayBinMapper.map(
            day: day,
            segments: segments,
            gaps: gaps,
            loudness: loudness
        )
        cacheByDay[key] = mapped
        return mapped
    }

    private func dayKey(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}

private struct CalendarSourcesSheet: View {
    @ObservedObject var service: CalendarOverlayService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calendar Sources")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Import ICS") {
                    Task { @MainActor in
                        await service.importICS()
                    }
                }
            }

            if !service.systemAccessGranted {
                Text("System calendar access is not granted. ICS import still works.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            List(service.sourceItems) { source in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: source.colorHex))
                        .frame(width: 8, height: 8)
                    Text(source.displayName)
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { source.enabled },
                        set: { enabled in
                            Task { @MainActor in
                                await service.setSourceEnabled(id: source.id, kind: source.kind, enabled: enabled)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        }
        .padding(14)
        .onAppear {
            Task { @MainActor in
                await service.reload(for: Date())
            }
        }
    }
}
