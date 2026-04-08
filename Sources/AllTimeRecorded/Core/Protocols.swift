import Foundation

@MainActor
protocol RecordingService: AnyObject {
    func start()
    func stop(reason: RecordingStopReason)
    func currentState() -> RecorderState
    func todayBins() -> [DayBin]
}

protocol PowerAssertionService: AnyObject {
    func acquireNoIdleSleepAssertion()
    func releaseAssertion()
}

protocol DiskGuardService: AnyObject {
    func checkFreeSpaceBytes() -> Int64
    func isBelowThreshold() -> Bool
}

@MainActor
protocol CalendarOverlayProviding: AnyObject {
    var currentEvents: [CalendarOverlayEvent] { get }
    var currentArcs: [CalendarArcSegment] { get }
    var sourceItems: [CalendarSourceItem] { get }
    var systemAccessGranted: Bool { get }
    func reload(for day: Date) async
}

@MainActor
protocol ModelAssetManaging: AnyObject {
    var modelID: String { get }
    var state: ModelDownloadState { get }
    func ensureModelReady() async
}

@MainActor
protocol TranscriptionScheduling: AnyObject {
    func start()
    func stop()
    func forceTranscribeAll() async
}
