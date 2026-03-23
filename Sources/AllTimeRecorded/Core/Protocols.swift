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
