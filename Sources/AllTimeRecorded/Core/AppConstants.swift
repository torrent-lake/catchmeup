import Foundation

enum AppConstants {
    static let appName = "AllTimeRecorded"
    static let segmentDuration: TimeInterval = 30 * 60
    static let loudnessSampleInterval: TimeInterval = 5
    static let diskLowThresholdBytes: Int64 = 5 * 1024 * 1024 * 1024
    static let diskResumeThresholdBytes: Int64 = 6 * 1024 * 1024 * 1024
    static let diskCheckInterval: TimeInterval = 60
    static let wakeRecoveryDelay: TimeInterval = 2.0
    static let inputRecoveryDelay: TimeInterval = 0.8
}
