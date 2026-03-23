import AVFoundation
import Foundation

@MainActor
final class DefaultRecordingService: NSObject, RecordingService, AVAudioRecorderDelegate {
    var onSnapshot: ((RecordingSnapshot) -> Void)?

    private let paths: AppPaths
    private let eventStore: EventStore
    private let powerAssertionService: PowerAssertionService
    private let diskGuardService: DefaultDiskGuardService
    private let inputDeviceMonitor: DefaultInputDeviceMonitor
    private let calendar: Calendar
    private let fileManager: FileManager

    private var recorder: AVAudioRecorder?
    private var currentSegmentStart: Date?
    private var currentSegmentTempURL: URL?
    private var currentSourceDeviceID: UInt32 = 0
    private var maintenanceTimer: Timer?
    private var rotationTimer: Timer?
    private var meterTimer: Timer?
    private var pendingResumeWorkItem: DispatchWorkItem?
    private var pendingGapStarts: [GapReason: Date] = [:]
    private var segments: [RecordingSegment]
    private var gaps: [GapEvent]
    private var loudnessEvents: [LoudnessEvent]
    private var state: RecorderState = .recovering
    private var freeBytesCache: Int64 = 0
    private var isRunning = false

    init(
        paths: AppPaths,
        eventStore: EventStore,
        powerAssertionService: PowerAssertionService,
        diskGuardService: DefaultDiskGuardService,
        inputDeviceMonitor: DefaultInputDeviceMonitor = DefaultInputDeviceMonitor(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.eventStore = eventStore
        self.powerAssertionService = powerAssertionService
        self.diskGuardService = diskGuardService
        self.inputDeviceMonitor = inputDeviceMonitor
        self.calendar = calendar
        self.fileManager = fileManager

        let loaded = eventStore.loadTimelineData()
        segments = loaded.segments
        gaps = loaded.gaps
        loudnessEvents = loaded.loudness

        super.init()

        let previousLaunchWasClean = eventStore.previousLaunchWasClean()
        let recovered = eventStore.recoverOpenSegments(currentDate: Date())
        if !recovered.isEmpty {
            segments.append(contentsOf: recovered)
            if let lastRecoveredEnd = recovered.map(\.endAt).max() {
                appendGap(startAt: lastRecoveredEnd, endAt: Date(), reason: .appRelaunchRecovery)
            }
        } else if !previousLaunchWasClean, let lastKnownEnd = lastKnownEventEndDate() {
            appendGap(startAt: lastKnownEnd, endAt: Date(), reason: .appRelaunchRecovery)
        }
        segments.sort { $0.startAt < $1.startAt }
        gaps.sort { $0.startAt < $1.startAt }
        eventStore.markLaunchUnclean()
        publishSnapshot()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        freeBytesCache = diskGuardService.checkFreeSpaceBytes()
        powerAssertionService.acquireNoIdleSleepAssertion()
        startMaintenanceLoop()
        inputDeviceMonitor.start { [weak self] in
            Task { @MainActor in
                self?.handleDefaultInputChange()
            }
        }

        if diskGuardService.isBelowThreshold() {
            state = .pausedLowDisk
            openGapIfNeeded(reason: .lowDiskPause)
            publishSnapshot()
            return
        }

        if !startNewSegment(closingGap: nil) {
            state = .recovering
        }
        publishSnapshot()
    }

    func stop(reason: RecordingStopReason) {
        switch reason {
        case .userQuit:
            stopTimers()
            pendingResumeWorkItem?.cancel()
            pendingResumeWorkItem = nil
            finishCurrentSegment(stopReason: reason)
            inputDeviceMonitor.stop()
            powerAssertionService.releaseAssertion()
            isRunning = false
            state = .recovering
            publishSnapshot()

        case .forcedSleep:
            stopAndOpenGap(reason: .forcedSleep, nextState: .recovering)

        case .lowDiskPause:
            stopAndOpenGap(reason: .lowDiskPause, nextState: .pausedLowDisk)

        case .inputDeviceLost:
            stopAndOpenGap(reason: .inputDeviceLost, nextState: .recovering)

        case .internalRecovery:
            finishCurrentSegment(stopReason: reason)
            state = .recovering
            publishSnapshot()
        }
    }

    func currentState() -> RecorderState {
        state
    }

    func todayBins() -> [DayBin] {
        buildSnapshot().bins
    }

    func handleWillSleep() {
        guard isRunning else { return }
        stop(reason: .forcedSleep)
    }

    func handleDidWake() {
        guard isRunning else { return }
        scheduleResume(after: AppConstants.wakeRecoveryDelay, closingGap: .forcedSleep)
    }

    func handleDefaultInputChange() {
        guard isRunning else { return }
        guard state == .recording else { return }
        stop(reason: .inputDeviceLost)
        scheduleResume(after: AppConstants.inputRecoveryDelay, closingGap: .inputDeviceLost)
    }

    private func stopAndOpenGap(reason: GapReason, nextState: RecorderState) {
        finishCurrentSegment(stopReason: .internalRecovery)
        openGapIfNeeded(reason: reason)
        state = nextState
        publishSnapshot()
    }

    private func openGapIfNeeded(reason: GapReason) {
        if pendingGapStarts[reason] == nil {
            pendingGapStarts[reason] = Date()
        }
    }

    private func closeGapIfNeeded(reason: GapReason, at endAt: Date = Date()) {
        guard let startAt = pendingGapStarts.removeValue(forKey: reason) else { return }
        appendGap(startAt: startAt, endAt: max(startAt, endAt), reason: reason)
    }

    private func appendGap(startAt: Date, endAt: Date, reason: GapReason) {
        guard endAt >= startAt else { return }
        let event = GapEvent(
            id: UUID(),
            startAt: startAt,
            endAt: endAt,
            reason: reason
        )
        gaps.append(event)
        eventStore.appendGap(event)
    }

    private func startMaintenanceLoop() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.diskCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.maintenanceTick()
            }
        }
        maintenanceTick()
    }

    private func stopTimers() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func maintenanceTick() {
        freeBytesCache = diskGuardService.checkFreeSpaceBytes()

        if state == .recording, diskGuardService.isBelowThreshold() {
            stop(reason: .lowDiskPause)
        } else if state == .pausedLowDisk, diskGuardService.isAboveResumeThreshold() {
            scheduleResume(after: 0.5, closingGap: .lowDiskPause)
        } else {
            publishSnapshot()
        }
    }

    private func scheduleResume(after delay: TimeInterval, closingGap: GapReason) {
        pendingResumeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.isRunning else { return }
                guard !self.diskGuardService.isBelowThreshold() else {
                    self.state = .pausedLowDisk
                    self.publishSnapshot()
                    return
                }
                let started = self.startNewSegment(closingGap: closingGap)
                self.state = started ? .recording : .recovering
                self.publishSnapshot()
            }
        }
        pendingResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startNewSegment(closingGap: GapReason?) -> Bool {
        rotationTimer?.invalidate()
        freeBytesCache = diskGuardService.checkFreeSpaceBytes()
        guard !diskGuardService.isBelowThreshold() else {
            state = .pausedLowDisk
            return false
        }

        let now = Date()
        let dayDirectory = paths.audioDirectory(for: now)
        try? fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        let openFilename = "\(AppDateFormatter.fileTimestamp(now))__open.m4a"
        let tempURL = dayDirectory.appendingPathComponent(openFilename, isDirectory: false)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        guard let recorder = try? AVAudioRecorder(url: tempURL, settings: settings) else {
            return false
        }
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            return false
        }

        self.recorder = recorder
        currentSegmentStart = now
        currentSegmentTempURL = tempURL
        currentSourceDeviceID = DefaultInputDeviceMonitor.currentDefaultInputDeviceID()
        state = .recording

        if let closingGap {
            closeGapIfNeeded(reason: closingGap, at: now)
        }

        startMeteringLoop()

        rotationTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.segmentDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rotateSegment()
            }
        }

        return true
    }

    private func rotateSegment() {
        guard isRunning else { return }
        finishCurrentSegment(stopReason: .internalRecovery)
        _ = startNewSegment(closingGap: nil)
        publishSnapshot()
    }

    private func finishCurrentSegment(stopReason: RecordingStopReason) {
        rotationTimer?.invalidate()
        rotationTimer = nil
        meterTimer?.invalidate()
        meterTimer = nil

        guard let recorder, let startAt = currentSegmentStart, let tempURL = currentSegmentTempURL else {
            self.recorder = nil
            currentSegmentStart = nil
            currentSegmentTempURL = nil
            return
        }

        recorder.stop()
        let endAt = Date()
        let finalURL = finalizeSegmentFile(tempURL: tempURL, startAt: startAt, endAt: endAt)
        let bytes = fileSize(for: finalURL)
        let segment = RecordingSegment(
            id: UUID(),
            startAt: startAt,
            endAt: max(startAt, endAt),
            fileURL: finalURL,
            bytes: bytes,
            sourceDeviceID: currentSourceDeviceID
        )
        segments.append(segment)
        eventStore.appendSegment(segment)

        self.recorder = nil
        currentSegmentStart = nil
        currentSegmentTempURL = nil

        if stopReason == .userQuit {
            pendingGapStarts.removeAll()
        }
    }

    private func finalizeSegmentFile(tempURL: URL, startAt: Date, endAt: Date) -> URL {
        let filename = "\(AppDateFormatter.fileTimestamp(startAt))__\(AppDateFormatter.fileTimestamp(max(startAt, endAt))).m4a"
        var finalURL = tempURL.deletingLastPathComponent().appendingPathComponent(filename, isDirectory: false)
        if fileManager.fileExists(atPath: finalURL.path) {
            let uniqueName = "\(AppDateFormatter.fileTimestamp(startAt))__\(AppDateFormatter.fileTimestamp(max(startAt, endAt)))__\(UUID().uuidString.prefix(6)).m4a"
            finalURL = tempURL.deletingLastPathComponent().appendingPathComponent(uniqueName, isDirectory: false)
        }
        try? fileManager.moveItem(at: tempURL, to: finalURL)
        return fileManager.fileExists(atPath: finalURL.path) ? finalURL : tempURL
    }

    private func fileSize(for url: URL) -> Int64 {
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    private func lastKnownEventEndDate() -> Date? {
        let latestSegmentEnd = segments.map(\.endAt).max()
        let latestGapEnd = gaps.map(\.endAt).max()
        return [latestSegmentEnd, latestGapEnd].compactMap { $0 }.max()
    }

    private func buildSnapshot() -> RecordingSnapshot {
        var runtimeSegments = segments
        if let startAt = currentSegmentStart, let currentURL = currentSegmentTempURL {
            runtimeSegments.append(
                RecordingSegment(
                    id: UUID(),
                    startAt: startAt,
                    endAt: Date(),
                    fileURL: currentURL,
                    bytes: fileSize(for: currentURL),
                    sourceDeviceID: currentSourceDeviceID
                )
            )
        }

        var runtimeGaps = gaps
        let now = Date()
        for (reason, startAt) in pendingGapStarts {
            runtimeGaps.append(
                GapEvent(
                    id: UUID(),
                    startAt: startAt,
                    endAt: now,
                    reason: reason
                )
            )
        }

        let bins = DayBinMapper.map(
            day: now,
            segments: runtimeSegments,
            gaps: runtimeGaps,
            loudness: loudnessEvents,
            calendar: calendar
        )
        let durations = DayBinMapper.durations(
            day: now,
            segments: runtimeSegments,
            gaps: runtimeGaps,
            calendar: calendar
        )

        return RecordingSnapshot(
            state: state,
            bins: bins,
            recordedSecondsToday: durations.recordedSeconds,
            gapSecondsToday: durations.gapSeconds,
            freeSpaceBytes: freeBytesCache,
            updatedAt: now
        )
    }

    private func publishSnapshot() {
        onSnapshot?(buildSnapshot())
    }

    private func startMeteringLoop() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.loudnessSampleInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.meterTick()
            }
        }
        meterTick()
    }

    private func meterTick() {
        guard state == .recording else { return }
        guard let recorder else { return }
        recorder.updateMeters()
        let normalized = normalizedLoudness(from: recorder.averagePower(forChannel: 0))
        let sample = LoudnessEvent(id: UUID(), sampledAt: Date(), normalizedLevel: normalized)
        loudnessEvents.append(sample)
        eventStore.appendLoudness(sample)
        publishSnapshot()
    }

    private func normalizedLoudness(from averagePower: Float) -> Double {
        let clamped = min(0, max(-55, averagePower))
        return Double((clamped + 55) / 55)
    }
}
