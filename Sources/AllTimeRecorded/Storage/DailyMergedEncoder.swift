@preconcurrency import AVFoundation
import Foundation

enum DailyMergedEncoderError: LocalizedError {
    case missingAudioTrack
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case readerStartFailed(String)
    case writerStartFailed(String)
    case readerFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioTrack:
            return "No audio track found in composition."
        case .cannotAddReaderOutput:
            return "Unable to add reader output."
        case .cannotAddWriterInput:
            return "Unable to add writer input."
        case .readerStartFailed(let message):
            return "Reader failed to start: \(message)"
        case .writerStartFailed(let message):
            return "Writer failed to start: \(message)"
        case .readerFailed(let message):
            return "Reader failed while encoding: \(message)"
        case .writerFailed(let message):
            return "Writer failed while encoding: \(message)"
        }
    }
}

struct DailyMergedEncoder: Sendable {
    private let sampleRate: Int
    private let channels: Int
    private let bitRate: Int
    private let quality: Int

    init(
        sampleRate: Int = AppConstants.dailyMergeSampleRate,
        channels: Int = AppConstants.dailyMergeChannels,
        bitRate: Int = AppConstants.dailyMergeBitRate,
        quality: Int = AppConstants.dailyMergeAudioQuality
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.quality = quality
    }

    func encode(composition: AVComposition, to outputURL: URL) async throws {
        guard let track = composition.tracks(withMediaType: .audio).first else {
            throw DailyMergedEncoderError.missingAudioTrack
        }

        let reader = try AVAssetReader(asset: composition)
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerOutputSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw DailyMergedEncoderError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: quality,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw DailyMergedEncoderError.cannotAddWriterInput
        }
        writer.add(writerInput)

        try await transcode(
            reader: reader,
            readerOutput: readerOutput,
            writer: writer,
            writerInput: writerInput
        )
    }

    private func transcode(
        reader: AVAssetReader,
        readerOutput: AVAssetReaderTrackOutput,
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completionLock = NSLock()
            var finished = false

            func complete(_ result: Result<Void, Error>) {
                completionLock.lock()
                defer { completionLock.unlock() }
                guard !finished else { return }
                finished = true
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            guard writer.startWriting() else {
                let message = writer.error?.localizedDescription ?? "unknown"
                complete(.failure(DailyMergedEncoderError.writerStartFailed(message)))
                return
            }
            guard reader.startReading() else {
                writer.cancelWriting()
                let message = reader.error?.localizedDescription ?? "unknown"
                complete(.failure(DailyMergedEncoderError.readerStartFailed(message)))
                return
            }

            writer.startSession(atSourceTime: .zero)
            let queue = DispatchQueue(label: "AllTimeRecorded.DailyMergedEncoder")

            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if reader.status == .failed || reader.status == .cancelled {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        let message = reader.error?.localizedDescription ?? "status \(reader.status.rawValue)"
                        complete(.failure(DailyMergedEncoderError.readerFailed(message)))
                        return
                    }

                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            switch writer.status {
                            case .completed:
                                if reader.status == .completed {
                                    complete(.success(()))
                                } else {
                                    let message = reader.error?.localizedDescription ?? "status \(reader.status.rawValue)"
                                    complete(.failure(DailyMergedEncoderError.readerFailed(message)))
                                }
                            case .failed, .cancelled:
                                let message = writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"
                                complete(.failure(DailyMergedEncoderError.writerFailed(message)))
                            default:
                                complete(.failure(DailyMergedEncoderError.writerFailed("unexpected status \(writer.status.rawValue)")))
                            }
                        }
                        return
                    }

                    guard writerInput.append(sampleBuffer) else {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        let message = writer.error?.localizedDescription ?? "append failed"
                        complete(.failure(DailyMergedEncoderError.writerFailed(message)))
                        return
                    }
                }
            }
        }
    }
}
