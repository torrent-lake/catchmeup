import Foundation

final class DefaultDiskGuardService: DiskGuardService {
    private let fileManager: FileManager
    private let paths: AppPaths

    init(fileManager: FileManager = .default, paths: AppPaths = AppPaths()) {
        self.fileManager = fileManager
        self.paths = paths
    }

    func checkFreeSpaceBytes() -> Int64 {
        do {
            let values = try paths.applicationSupportRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available
            }
        } catch {
            if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let free = attrs[.systemFreeSize] as? NSNumber {
                return free.int64Value
            }
        }
        return 0
    }

    func isBelowThreshold() -> Bool {
        checkFreeSpaceBytes() < AppConstants.diskLowThresholdBytes
    }

    func isAboveResumeThreshold() -> Bool {
        checkFreeSpaceBytes() > AppConstants.diskResumeThresholdBytes
    }
}

