import Foundation

struct AppPaths {
    let fileManager: FileManager
    let calendar: Calendar

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    var applicationSupportRoot: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(AppConstants.appName, isDirectory: true)
    }

    var audioRoot: URL {
        applicationSupportRoot.appendingPathComponent("audio", isDirectory: true)
    }

    var metaRoot: URL {
        applicationSupportRoot.appendingPathComponent("meta", isDirectory: true)
    }

    var modelsRoot: URL {
        applicationSupportRoot.appendingPathComponent("models", isDirectory: true)
    }

    var transcriptsRoot: URL {
        applicationSupportRoot.appendingPathComponent("transcripts", isDirectory: true)
    }

    var calendarRoot: URL {
        applicationSupportRoot.appendingPathComponent("calendar", isDirectory: true)
    }

    var eventsFileURL: URL {
        metaRoot.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    var lifecycleFileURL: URL {
        metaRoot.appendingPathComponent("lifecycle.flag", isDirectory: false)
    }

    func audioDirectory(for day: Date) -> URL {
        let components = calendar.dateComponents(in: .current, from: day)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let dayValue = components.day ?? 1
        let folder = String(format: "%04d-%02d-%02d", year, month, dayValue)
        return audioRoot.appendingPathComponent(folder, isDirectory: true)
    }

    func ensureBaseDirectories() throws {
        try fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metaRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transcriptsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: calendarRoot, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: eventsFileURL.path) {
            fileManager.createFile(atPath: eventsFileURL.path, contents: nil)
        }
    }
}
