import Foundation
import AVFoundation

enum AppConstants {
    static let appName = "AllTimeRecorded"
    static let segmentDuration: TimeInterval = 30 * 60
    static let loudnessSampleInterval: TimeInterval = 5
    static let diskLowThresholdBytes: Int64 = 5 * 1024 * 1024 * 1024
    static let diskResumeThresholdBytes: Int64 = 6 * 1024 * 1024 * 1024
    static let diskCheckInterval: TimeInterval = 60
    static let wakeRecoveryDelay: TimeInterval = 2.0
    static let inputRecoveryDelay: TimeInterval = 0.8
    static let dailyMergeSampleRate = 22_050
    static let dailyMergeChannels = 1
    static let dailyMergeBitRate = 20_000
    static let dailyMergeAudioQuality = AVAudioQuality.high.rawValue

    static let recordingSampleRate = 22_050
    static let recordingChannels = 1
    static let recordingBitRate = 24_000

    static let transcriptionPollInterval: TimeInterval = 10 * 60
    static let transcriptionIdleSecondsThreshold: TimeInterval = 60

    static let whisperModelID = "large-v3-turbo-q5"
    static let whisperModelFileName = "ggml-large-v3-turbo-q5_0.bin"
    static let whisperModelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    static let whisperModelSHA256: String? = nil
    static let whisperModelMinimumSizeBytes: Int64 = 400 * 1024 * 1024
}
