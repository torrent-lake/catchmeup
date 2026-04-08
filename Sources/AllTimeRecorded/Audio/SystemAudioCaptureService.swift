import AVFoundation
import Foundation
import ScreenCaptureKit

/// Handles the AVAssetWriter on the capture queue. Thread-safe via `lock`.
private final class AudioWriterSink: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var sessionStarted = false
    private var finished = false

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        guard writer.status == .writing else { return }
        guard input.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        input.append(sampleBuffer)
    }

    func finish() async -> Bool {
        let shouldFinish: Bool = lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldFinish else {
            return lock.withLock { writer.status == .completed }
        }

        input.markAsFinished()
        if writer.status == .writing {
            await writer.finishWriting()
        }
        return writer.status == .completed
    }
}

@MainActor
final class SystemAudioCaptureService: NSObject {
    private(set) var isRecording = false
    private var stream: SCStream?
    private var sink: AudioWriterSink?
    /// Non-isolated reference for the SCStreamOutput callback.
    nonisolated(unsafe) private var activeSink: AudioWriterSink?
    private var outputURL: URL?
    private let delegateQueue = DispatchQueue(label: "alltimerecorded.system-audio-capture")

    func start(outputURL: URL) async -> Bool {
        guard !isRecording else { return true }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            return false
        }

        guard let display = content.displays.first else { return false }

        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == selfBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = AppConstants.systemAudioSampleRate
        config.channelCount = AppConstants.systemAudioChannels
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
            let inputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: AppConstants.systemAudioSampleRate,
                AVNumberOfChannelsKey: AppConstants.systemAudioChannels,
                AVEncoderBitRateKey: AppConstants.systemAudioBitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: inputSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            guard writer.startWriting() else { return false }

            self.sink = AudioWriterSink(writer: writer, input: input)
            self.activeSink = self.sink
            self.outputURL = outputURL
        } catch {
            return false
        }

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: delegateQueue)
            try await scStream.startCapture()
        } catch {
            _ = await sink?.finish()
            sink = nil
            activeSink = nil
            self.outputURL = nil
            return false
        }

        self.stream = scStream
        self.isRecording = true
        return true
    }

    func stop() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        let url = outputURL
        let ok = await sink?.finish() ?? false

        sink = nil
        activeSink = nil
        outputURL = nil

        return ok ? url : nil
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        activeSink?.append(sampleBuffer)
    }
}
