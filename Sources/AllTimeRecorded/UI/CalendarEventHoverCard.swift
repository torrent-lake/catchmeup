import SwiftUI

struct CalendarEventHoverCard: View {
    let arc: CalendarArcSegment

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: arc.startAt))-\(formatter.string(from: arc.endAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(arc.eventTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(timeRangeText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: arc.colorHex).opacity(0.95))
            Text(arc.sourceName)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: 164, alignment: .leading)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
