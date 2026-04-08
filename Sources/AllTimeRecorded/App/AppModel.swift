import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: RecordingSnapshot = .empty()
    @Published var highlightedTimeRanges: [DateInterval] = []

    func apply(snapshot: RecordingSnapshot) {
        self.snapshot = snapshot
    }

    func setState(_ state: RecorderState) {
        snapshot = RecordingSnapshot(
            state: state,
            bins: snapshot.bins,
            recordedSecondsToday: snapshot.recordedSecondsToday,
            gapSecondsToday: snapshot.gapSecondsToday,
            freeSpaceBytes: snapshot.freeSpaceBytes,
            updatedAt: Date()
        )
    }

    var stateTitle: String {
        switch snapshot.state {
        case .recording:
            return "Recording"
        case .pausedLowDisk:
            return "Low Disk"
        case .blockedNoPermission:
            return "Mic Blocked"
        case .recovering:
            return "Recovering"
        }
    }

    var freeSpaceLabel: String {
        ByteCountFormatter.string(fromByteCount: snapshot.freeSpaceBytes, countStyle: .file)
    }

    var recordedTodayLabel: String {
        snapshot.recordedSecondsToday.compactClock
    }

    var gapTodayLabel: String {
        snapshot.gapSecondsToday.compactClock
    }

    func recordedTodayLabel(at now: Date) -> String {
        extrapolatedRecordedSeconds(at: now).compactClock
    }

    func gapTodayLabel(at now: Date) -> String {
        snapshot.gapSecondsToday.compactClock
    }

    private func extrapolatedRecordedSeconds(at now: Date) -> TimeInterval {
        guard snapshot.state == .recording else {
            return snapshot.recordedSecondsToday
        }
        return snapshot.recordedSecondsToday + max(0, now.timeIntervalSince(snapshot.updatedAt))
    }
}

private extension TimeInterval {
    var compactClock: String {
        let value = max(0, Int(self))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
