import Foundation

public enum ICSExporter {
    public static func export(reminders: [ReminderItem], history: [HistoryEntry] = [], now: Date = Date()) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//SpacedOut//Desktop Reminders//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        let stamp = formatUTC(now)

        for item in reminders {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(item.id.uuidString)@spacedout.app")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART:\(formatUTC(item.targetDate))")
            lines.append("DTEND:\(formatUTC(item.targetDate.addingTimeInterval(60)))")
            lines.append("SUMMARY:\(escapeText(item.displayTitle))")
            lines.append("DESCRIPTION:\(escapeText("Created in SpacedOut (\(item.durationSeconds / 60)m)"))")
            lines.append("BEGIN:VALARM")
            lines.append("ACTION:DISPLAY")
            lines.append("DESCRIPTION:\(escapeText(item.displayTitle))")
            lines.append("TRIGGER:PT0S")
            lines.append("END:VALARM")
            lines.append("END:VEVENT")
        }

        for entry in history {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(entry.id.uuidString)@spacedout.app")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART:\(formatUTC(entry.createdAt))")
            lines.append("DTEND:\(formatUTC(entry.finishedAt))")
            let statusTag = entry.outcome == .completed ? "Completed" : "Dismissed"
            lines.append("SUMMARY:\(escapeText("[\(statusTag)] \(entry.displayTitle)"))")
            lines.append("DESCRIPTION:\(escapeText("Planned: \(entry.plannedDurationSeconds)s, Snoozes: \(entry.snoozeCount)"))")
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func formatUTC(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
