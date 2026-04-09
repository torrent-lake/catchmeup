import EventKit
import Foundation

/// Sendable snapshot of an EKReminder's relevant fields. EKReminder itself
/// is not Sendable, so we extract the data we need on the callback thread.
struct SendableReminder: Sendable {
    let calendarItemIdentifier: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let completionDate: Date?
    let dueDateComponents: DateComponents?
    let priority: Int
    let calendarTitle: String

    init(_ reminder: EKReminder) {
        self.calendarItemIdentifier = reminder.calendarItemIdentifier
        self.title = reminder.title ?? "(Untitled)"
        self.notes = reminder.notes
        self.isCompleted = reminder.isCompleted
        self.completionDate = reminder.completionDate
        self.dueDateComponents = reminder.dueDateComponents
        self.priority = reminder.priority
        self.calendarTitle = reminder.calendar?.title ?? ""
    }
}

/// Data source that queries Reminders via EventKit.
/// Fetches incomplete reminders and keyword-matches against the question.
final class RemindersDataSource: DataSource, @unchecked Sendable {
    let id = "reminders"
    let displayName = "Reminders"
    let requiresConsent = false  // user's own reminders

    private let eventStore = EKEventStore()

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        let hasAccess = await requestAccess()
        guard hasAccess else { return [] }

        let calendars = eventStore.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }

        // Fetch incomplete reminders
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: Date().addingTimeInterval(-90 * 86_400),  // past 90 days
            ending: Date().addingTimeInterval(30 * 86_400),                // next 30 days
            calendars: nil
        )

        let reminders = await fetchReminders(matching: predicate)

        // Also fetch recently completed
        let completedPredicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: Date().addingTimeInterval(-14 * 86_400),
            ending: Date(),
            calendars: nil
        )

        let completedReminders = await fetchReminders(matching: completedPredicate)

        let allReminders = reminders + completedReminders
        let keywords = CalendarDataSource.extractKeywords(from: question)

        let lowerQuestion = question.lowercased()
        let generalMatch = lowerQuestion.contains("remind")
            || lowerQuestion.contains("todo")
            || lowerQuestion.contains("task")
            || lowerQuestion.contains("提醒")
            || lowerQuestion.contains("待办")
            || lowerQuestion.contains("忘记")
            || lowerQuestion.contains("forget")
            || lowerQuestion.contains("schedule")
            || lowerQuestion.contains("日程")
            || lowerQuestion.contains("today")
            || lowerQuestion.contains("tomorrow")
            || lowerQuestion.contains("今天")
            || lowerQuestion.contains("明天")
            || lowerQuestion.contains("deadline")
            || lowerQuestion.contains("due")

        let matched: [(reminder: SendableReminder, relevance: Double)] = allReminders.compactMap { reminder in
            let searchable = [
                reminder.title,
                reminder.notes ?? "",
            ].joined(separator: " ").lowercased()

            let hits = keywords.filter { searchable.contains($0) }

            if hits.isEmpty && !generalMatch { return nil }
            let relevance = hits.isEmpty ? 0.3 : Double(hits.count) / Double(max(keywords.count, 1))
            return (reminder, relevance)
        }

        let sorted = matched
            .sorted { $0.relevance > $1.relevance }
            .prefix(topK)

        return sorted.map { item in
            let reminder = item.reminder
            return SourceChunk(
                id: "reminders#\(reminder.calendarItemIdentifier)",
                sourceID: "reminders",
                title: reminder.title,
                body: Self.formatReminderBody(reminder),
                timestamp: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    ?? reminder.completionDate,
                originURI: "x-apple-reminderkit://\(reminder.calendarItemIdentifier)",
                score: item.relevance
            )
        }
    }

    /// Wrapper to bridge EKEventStore's callback-based reminder fetch into
    /// async/await while handling Swift 6's Sendable requirements.
    private func fetchReminders(matching predicate: NSPredicate) async -> [SendableReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                let sendable = (result ?? []).map { SendableReminder($0) }
                continuation.resume(returning: sendable)
            }
        }
    }

    private func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private static func formatReminderBody(_ reminder: SendableReminder) -> String {
        var lines: [String] = []
        lines.append("Reminder: \(reminder.title)")
        if reminder.isCompleted {
            lines.append("Status: Completed")
            if let completionDate = reminder.completionDate {
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .short
                lines.append("Completed: \(df.string(from: completionDate))")
            }
        } else {
            lines.append("Status: Incomplete")
        }
        if let dueDate = reminder.dueDateComponents,
           let date = Calendar.current.date(from: dueDate) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            lines.append("Due: \(df.string(from: date))")
        }
        if let priority = priorityLabel(reminder.priority) {
            lines.append("Priority: \(priority)")
        }
        if !reminder.calendarTitle.isEmpty {
            lines.append("List: \(reminder.calendarTitle)")
        }
        if let notes = reminder.notes, !notes.isEmpty {
            lines.append("Notes: \(String(notes.prefix(500)))")
        }
        return lines.joined(separator: "\n")
    }

    private static func priorityLabel(_ priority: Int) -> String? {
        switch priority {
        case 1...4: return "High"
        case 5: return "Medium"
        case 6...9: return "Low"
        default: return nil
        }
    }
}
