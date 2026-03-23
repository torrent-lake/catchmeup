import AVFoundation
import Foundation
import Testing
@testable import AllTimeRecorded

struct DailyMergedEncoderTests {
    @Test
    func encodeProducesM4AWithExpectedFormat() async throws {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("AllTimeRecordedTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDir) }

        let first = workDir.appendingPathComponent("first.caf")
        let second = workDir.appendingPathComponent("second.caf")
        try writeTone(to: first, duration: 0.9, frequency: 440)
        try writeTone(to: second, duration: 0.8, frequency: 510)

        let composition = try await compositionFromSources([first, second])
        let outputURL = workDir.appendingPathComponent("daily-merged.m4a")
        let encoder = DailyMergedEncoder()
        try await encoder.encode(composition: composition, to: outputURL)

        #expect(fileManager.fileExists(atPath: outputURL.path))
        let attrs = try fileManager.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        #expect(size > 0)

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 1.5)

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            Issue.record("Missing audio track in encoded output.")
            return
        }

        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let audioDesc = formatDescriptions.first,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc)
        else {
            Issue.record("Missing stream description for encoded output.")
            return
        }

        #expect(Int(stream.pointee.mSampleRate.rounded()) == AppConstants.dailyMergeSampleRate)
        #expect(Int(stream.pointee.mChannelsPerFrame) == AppConstants.dailyMergeChannels)

        let estimatedDataRate = try await track.load(.estimatedDataRate)
        #expect(estimatedDataRate > 4_000)
        #expect(estimatedDataRate < 30_000)
    }

    @Test
    func encodeFailsForEmptyComposition() async {
        let encoder = DailyMergedEncoder()
        let composition = AVMutableComposition()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("AllTimeRecorded-empty-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            try await encoder.encode(composition: composition, to: outputURL)
            Issue.record("Expected encoding to fail for empty composition.")
        } catch {
            #expect(error is DailyMergedEncoderError)
        }
    }

    private func compositionFromSources(_ sourceURLs: [URL]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let targetTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            struct MissingTrackError: Error {}
            throw MissingTrackError()
        }

        var cursor = CMTime.zero
        for url in sourceURLs {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try targetTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: cursor)
            cursor = cursor + duration
        }
        return composition
    }

    private func writeTone(to url: URL, duration: TimeInterval, frequency: Float) throws {
        let sampleRate = Double(AppConstants.dailyMergeSampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(AppConstants.dailyMergeChannels)),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(duration * sampleRate)
              ),
              let channelData = buffer.floatChannelData
        else {
            struct AudioBufferError: Error {}
            throw AudioBufferError()
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        buffer.frameLength = frameCount
        let channel = channelData[0]
        for frame in 0..<Int(frameCount) {
            let value = sinf(2 * .pi * frequency * Float(frame) / Float(sampleRate)) * 0.15
            channel[frame] = value
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}
