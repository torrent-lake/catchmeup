import Foundation

final class CalendarSourcesStore {
    struct PersistedSource: Codable, Hashable {
        let id: String
        let bookmarkDataBase64: String
        let displayName: String
        let colorHex: String
        let enabled: Bool
    }

    struct PersistedConfig: Codable {
        var icsSources: [PersistedSource]
        var enabledSystemCalendarIDs: [String]
        var updatedAt: Date

        static let empty = PersistedConfig(
            icsSources: [],
            enabledSystemCalendarIDs: [],
            updatedAt: Date()
        )
    }

    private let paths: AppPaths
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var configURL: URL {
        paths.metaRoot.appendingPathComponent("calendar-sources.json", isDirectory: false)
    }

    func load() -> PersistedConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? decoder.decode(PersistedConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    func save(_ config: PersistedConfig) {
        var output = config
        output.updatedAt = Date()
        guard let data = try? encoder.encode(output) else { return }
        try? fileManager.createDirectory(at: paths.metaRoot, withIntermediateDirectories: true)
        try? data.write(to: configURL, options: .atomic)
    }

    func upsertICSSource(url: URL, colorHex: String) {
        var config = load()
        let id = "ics::\(url.path)"
        let displayName = url.deletingPathExtension().lastPathComponent
        let bookmark = (try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        let source = PersistedSource(
            id: id,
            bookmarkDataBase64: bookmark.base64EncodedString(),
            displayName: displayName.isEmpty ? url.lastPathComponent : displayName,
            colorHex: colorHex,
            enabled: true
        )
        if let index = config.icsSources.firstIndex(where: { $0.id == id }) {
            config.icsSources[index] = source
        } else {
            config.icsSources.append(source)
        }
        save(config)
    }

    func removeICSSource(id: String) {
        var config = load()
        config.icsSources.removeAll { $0.id == id }
        save(config)
    }

    func setSystemCalendar(id: String, enabled: Bool) {
        var config = load()
        var set = Set(config.enabledSystemCalendarIDs)
        if enabled {
            set.insert(id)
        } else {
            set.remove(id)
        }
        config.enabledSystemCalendarIDs = set.sorted()
        save(config)
    }

    func resolvedICSSources() -> [(source: PersistedSource, url: URL)] {
        let config = load()
        var output: [(source: PersistedSource, url: URL)] = []
        output.reserveCapacity(config.icsSources.count)

        for source in config.icsSources where source.enabled {
            guard let bookmarkData = Data(base64Encoded: source.bookmarkDataBase64) else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                continue
            }
            output.append((source, url))
        }
        return output
    }

    func enabledSystemCalendarIDs() -> Set<String> {
        Set(load().enabledSystemCalendarIDs)
    }
}
