import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class CalendarOverlayService: ObservableObject, CalendarOverlayProviding {
    @Published private(set) var currentEvents: [CalendarOverlayEvent] = []
    @Published private(set) var currentArcs: [CalendarArcSegment] = []
    @Published private(set) var sourceItems: [CalendarSourceItem] = []
    @Published private(set) var systemAccessGranted = false

    private let store: CalendarSourcesStore
    private let systemProvider: SystemCalendarProvider
    private let calendar: Calendar
    private var selectedDay: Date = Date()
    private var reloadGeneration: Int = 0
    private var icsCache: [String: CachedICSEvents] = [:]
    private var dayOverlayCache: [String: CachedOverlay] = [:]

    private struct CachedICSEvents {
        let sourcePath: String
        let contentModifiedAt: Date?
        let events: [CalendarOverlayEvent]
    }

    private struct CachedOverlay {
        let events: [CalendarOverlayEvent]
        let arcs: [CalendarArcSegment]
        let sources: [CalendarSourceItem]
    }

    init(
        store: CalendarSourcesStore = CalendarSourcesStore(),
        systemProvider: SystemCalendarProvider = SystemCalendarProvider(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.systemProvider = systemProvider
        self.calendar = calendar
    }

    func reload(for day: Date) async {
        selectedDay = day
        reloadGeneration += 1
        let generation = reloadGeneration

        let hasSystemAccess = await systemProvider.requestAccessIfNeeded()
        guard generation == reloadGeneration else { return }
        systemAccessGranted = hasSystemAccess

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let queryStart = dayStart.addingTimeInterval(-6 * 3600)
        let queryEnd = dayEnd.addingTimeInterval(6 * 3600)

        let config = store.load()
        var allEvents: [CalendarOverlayEvent] = []
        var allSources: [CalendarSourceItem] = []

        let icsSources = store.resolvedICSSources()
        let overlayCacheKey = makeOverlayCacheKey(
            day: dayStart,
            sources: icsSources,
            enabledSystemCalendarIDs: config.enabledSystemCalendarIDs,
            systemAccess: hasSystemAccess
        )

        if let cached = dayOverlayCache[overlayCacheKey] {
            currentEvents = cached.events
            currentArcs = cached.arcs
            sourceItems = cached.sources
            return
        }

        for (source, url) in icsSources {
            allSources.append(
                CalendarSourceItem(
                    id: source.id,
                    kind: .localICS,
                    displayName: source.displayName,
                    enabled: source.enabled,
                    colorHex: source.colorHex
                )
            )
            let parsed = await cachedICSEvents(for: source, url: url)
            guard generation == reloadGeneration else { return }
            allEvents.append(contentsOf: filterEvents(parsed, from: queryStart, to: queryEnd))
        }

        let calendars = systemProvider.availableCalendars()
        var systemEnabled = Set(config.enabledSystemCalendarIDs)

        // Auto-enable all system calendars on first launch (no config file yet).
        if systemEnabled.isEmpty && !calendars.isEmpty {
            systemEnabled = Set(calendars.map(\.id))
            // Persist so the user can selectively disable later.
            var updated = config
            updated.enabledSystemCalendarIDs = systemEnabled.sorted()
            store.save(updated)
        }

        for calendar in calendars {
            allSources.append(
                CalendarSourceItem(
                    id: calendar.id,
                    kind: .systemCalendar,
                    displayName: calendar.title,
                    enabled: systemEnabled.contains(calendar.id),
                    colorHex: calendar.colorHex
                )
            )
        }
        if hasSystemAccess {
            allEvents.append(contentsOf: systemProvider.events(from: queryStart, to: queryEnd, enabledCalendarIDs: systemEnabled))
        }

        guard generation == reloadGeneration else { return }
        let deduped = dedupe(allEvents)
        let mapped = CalendarArcMapper.map(day: day, events: deduped, calendar: calendar)
        let sortedSources = allSources.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        currentEvents = deduped
        currentArcs = mapped
        sourceItems = sortedSources
        dayOverlayCache[overlayCacheKey] = CachedOverlay(
            events: deduped,
            arcs: mapped,
            sources: sortedSources
        )
    }

    func importICS() async {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        panel.message = "Select one or more ICS files"
        panel.allowsMultipleSelection = true
        if let icsType = UTType(filenameExtension: "ics") {
            panel.allowedContentTypes = [icsType]
        }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            store.upsertICSSource(url: url, colorHex: nextColorHex(for: url.path))
        }
        icsCache.removeAll(keepingCapacity: true)
        dayOverlayCache.removeAll(keepingCapacity: true)
        await reload(for: selectedDay)
    }

    func removeICSSource(id: String) async {
        store.removeICSSource(id: id)
        icsCache.removeValue(forKey: id)
        dayOverlayCache.removeAll(keepingCapacity: true)
        await reload(for: selectedDay)
    }

    func setSourceEnabled(id: String, kind: CalendarSourceItem.Kind, enabled: Bool) async {
        switch kind {
        case .localICS:
            var config = store.load()
            if let index = config.icsSources.firstIndex(where: { $0.id == id }) {
                let source = config.icsSources[index]
                config.icsSources[index] = CalendarSourcesStore.PersistedSource(
                    id: source.id,
                    bookmarkDataBase64: source.bookmarkDataBase64,
                    displayName: source.displayName,
                    colorHex: source.colorHex,
                    enabled: enabled
                )
                store.save(config)
            }
            icsCache.removeValue(forKey: id)
        case .systemCalendar:
            store.setSystemCalendar(id: id, enabled: enabled)
        }
        dayOverlayCache.removeAll(keepingCapacity: true)
        await reload(for: selectedDay)
    }

    private func cachedICSEvents(
        for source: CalendarSourcesStore.PersistedSource,
        url: URL
    ) async -> [CalendarOverlayEvent] {
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = icsCache[source.id],
           cached.sourcePath == url.path,
           cached.contentModifiedAt == modifiedAt {
            return cached.events
        }

        let sourceID = source.id
        let sourceName = source.displayName
        let colorHex = source.colorHex
        let parseCalendar = calendar
        let parsed = await Task.detached(priority: .utility) {
            ICSBasicParser.parseEvents(
                at: url,
                sourceID: sourceID,
                sourceName: sourceName,
                colorHex: colorHex,
                defaultCalendar: parseCalendar
            )
        }.value

        icsCache[source.id] = CachedICSEvents(
            sourcePath: url.path,
            contentModifiedAt: modifiedAt,
            events: parsed
        )
        return parsed
    }

    private func makeOverlayCacheKey(
        day: Date,
        sources: [(source: CalendarSourcesStore.PersistedSource, url: URL)],
        enabledSystemCalendarIDs: [String],
        systemAccess: Bool
    ) -> String {
        let dayKey = dayKeyString(day)
        let icsTokens = sources.map { source, url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                .timeIntervalSince1970 ?? 0
            return "\(source.id)|\(url.path)|\(Int(modified))"
        }
        .sorted()
        .joined(separator: ";")
        let systemToken = enabledSystemCalendarIDs.sorted().joined(separator: ",")
        return "\(dayKey)#\(systemAccess ? "1" : "0")#\(systemToken)#\(icsTokens)"
    }

    private func dayKeyString(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    private func filterEvents(_ events: [CalendarOverlayEvent], from start: Date, to end: Date) -> [CalendarOverlayEvent] {
        events.filter { event in
            event.startAt < end && event.endAt > start
        }
    }

    private func dedupe(_ events: [CalendarOverlayEvent]) -> [CalendarOverlayEvent] {
        var seenUID: Set<String> = []
        var seenFallback: Set<String> = []
        var result: [CalendarOverlayEvent] = []
        result.reserveCapacity(events.count)

        for event in events.sorted(by: { $0.startAt < $1.startAt }) {
            if !event.uid.isEmpty {
                guard !seenUID.contains(event.uid) else { continue }
                seenUID.insert(event.uid)
            } else {
                let fallback = "\(event.title)|\(event.startAt.timeIntervalSince1970)|\(event.endAt.timeIntervalSince1970)|\(event.sourceID)"
                guard !seenFallback.contains(fallback) else { continue }
                seenFallback.insert(fallback)
            }
            result.append(event)
        }
        return result
    }

    private func nextColorHex(for seed: String) -> String {
        let palette = [
            "#6AF2FF",
            "#89FFBE",
            "#FFD77A",
            "#FF9EC8",
            "#C49DFF",
            "#8ED0FF",
        ]
        let index = abs(seed.hashValue) % palette.count
        return palette[index]
    }
}
