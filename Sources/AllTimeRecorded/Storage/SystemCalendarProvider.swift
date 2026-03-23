import AppKit
import EventKit
import Foundation

struct SystemCalendarDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorHex: String
}

@MainActor
final class SystemCalendarProvider {
    private let eventStore = EKEventStore()

    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    func availableCalendars() -> [SystemCalendarDescriptor] {
        eventStore.calendars(for: .event).map {
            SystemCalendarDescriptor(
                id: $0.calendarIdentifier,
                title: $0.title,
                colorHex: $0.cgColor?.hexString ?? "#6AD8FF"
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func events(
        from start: Date,
        to end: Date,
        enabledCalendarIDs: Set<String>
    ) -> [CalendarOverlayEvent] {
        let calendars = eventStore.calendars(for: .event).filter { enabledCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate).map { event in
            CalendarOverlayEvent(
                id: UUID(),
                uid: event.calendarItemIdentifier,
                title: event.title ?? "(Untitled Event)",
                startAt: event.startDate,
                endAt: max(event.startDate, event.endDate),
                sourceID: event.calendar.calendarIdentifier,
                sourceName: event.calendar.title,
                colorHex: event.calendar.cgColor?.hexString ?? "#6AD8FF",
                location: event.location,
                notePreview: event.notes
            )
        }
    }
}

private extension CGColor {
    var hexString: String? {
        guard let converted = NSColor(cgColor: self)?.usingColorSpace(.sRGB) else { return nil }
        let red = Int(converted.redComponent * 255)
        let green = Int(converted.greenComponent * 255)
        let blue = Int(converted.blueComponent * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
