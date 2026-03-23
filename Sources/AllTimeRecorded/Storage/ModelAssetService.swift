import CryptoKit
import Foundation

@MainActor
final class ModelAssetService: ObservableObject, ModelAssetManaging {
    @Published private(set) var state: ModelDownloadState = .idle
    private var isEnsuring = false

    let modelID: String
    private let modelURL: URL
    private let expectedSHA256: String?
    private let destinationURL: URL
    private let fileManager: FileManager
    private let minimumSizeBytes: Int64

    init(
        paths: AppPaths = AppPaths(),
        fileManager: FileManager = .default,
        modelID: String = AppConstants.whisperModelID,
        modelURL: URL = AppConstants.whisperModelURL,
        expectedSHA256: String? = AppConstants.whisperModelSHA256,
        minimumSizeBytes: Int64 = AppConstants.whisperModelMinimumSizeBytes
    ) {
        self.fileManager = fileManager
        self.modelID = modelID
        self.modelURL = modelURL
        self.expectedSHA256 = expectedSHA256
        self.destinationURL = paths.modelsRoot.appendingPathComponent(AppConstants.whisperModelFileName, isDirectory: false)
        self.minimumSizeBytes = minimumSizeBytes
        refreshStateFromDisk()
    }

    var modelPathURL: URL {
        destinationURL
    }

    var modelFileSizeBytes: Int64? {
        guard let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    var isLocalModelUsable: Bool {
        verifyExistingFast()
    }

    func refreshStateFromDisk() {
        if verifyExistingFast() {
            state = .ready(path: destinationURL.path)
        } else if case .downloading = state {
            // Keep current state while downloading.
        } else if case .verifying = state {
            // Keep current state while verifying.
        } else {
            state = .idle
        }
    }

    func ensureModelReady() async {
        guard !isEnsuring else { return }
        isEnsuring = true
        defer { isEnsuring = false }

        if verifyExistingFast() {
            if await verifyExisting() {
                state = .ready(path: destinationURL.path)
                return
            }
            try? fileManager.removeItem(at: destinationURL)
        }

        state = .downloading(progress: 0)
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (tempURL, _) = try await URLSession.shared.download(from: modelURL)
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            state = .verifying
            guard await verifyExisting() else {
                state = .failed(message: "Model file invalid")
                try? fileManager.removeItem(at: destinationURL)
                return
            }

            state = .ready(path: destinationURL.path)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func verifyExisting() async -> Bool {
        guard verifyExistingFast() else { return false }
        guard let expectedSHA256, !expectedSHA256.isEmpty else { return true }
        guard let data = try? Data(contentsOf: destinationURL, options: [.mappedIfSafe]) else { return false }
        let digest = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return digest.lowercased() == expectedSHA256.lowercased()
    }

    private func verifyExistingFast() -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path) else { return false }
        guard let size = modelFileSizeBytes, size >= minimumSizeBytes else { return false }
        return true
    }
}
