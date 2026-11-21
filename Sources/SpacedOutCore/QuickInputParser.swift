import Foundation

public enum ParsedTarget: Equatable, Sendable {
    case duration(seconds: Int)
    case clockTime(targetDate: Date, secondsFromNow: Int)
}

public struct ParsedReminderInput: Equatable, Sendable {
    public let title: String
    public let target: ParsedTarget
    public let matchedExplicitTime: Bool

    public init(title: String, target: ParsedTarget, matchedExplicitTime: Bool) {
        self.title = title
        self.target = target
        self.matchedExplicitTime = matchedExplicitTime
    }

    public var effectiveDurationSeconds: Int {
        switch target {
        case .duration(let seconds): return max(10, seconds)
        case .clockTime(_, let secondsFromNow): return max(10, secondsFromNow)
        }
    }

    public func previewBadge(at now: Date, calendar: Calendar = .current) -> String {
        switch target {
        case .duration(let seconds):
            let targetDate = now.addingTimeInterval(TimeInterval(seconds))
            return "\(Self.humanDuration(seconds)) · \(Self.formatTime(targetDate, calendar: calendar))"
        case .clockTime(let date, let secondsFromNow):
            return "At \(Self.formatTime(date, calendar: calendar)) · in \(Self.humanDuration(secondsFromNow))"
        }
    }

    private static func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let remSec = seconds % 60
        if hrs > 0 && mins > 0 { return "\(hrs)h \(mins)m" }
        if hrs > 0 { return "\(hrs)h" }
        if remSec > 0 { return "\(mins)m \(remSec)s" }
        return "\(mins)m"
    }

    private static func formatTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

public enum QuickInputParser {
    public static func parse(
        _ raw: String,
        now: Date = Date(),
        fallbackDurationSeconds: Int = 15 * 60,
        calendar: Calendar = .current
    ) -> ParsedReminderInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedReminderInput(title: "", target: .duration(seconds: max(10, fallbackDurationSeconds)), matchedExplicitTime: false)
        }

        if let bareMinutes = Double(trimmed), bareMinutes > 0, bareMinutes <= 1440 {
            let seconds = max(10, Int((bareMinutes * 60.0).rounded()))
            return ParsedReminderInput(title: "", target: .duration(seconds: seconds), matchedExplicitTime: false)
        }

        if let clockMatch = extractClockTime(from: trimmed, now: now, calendar: calendar) {
            return clockMatch
        }
        if let durationMatch = extractExplicitDuration(from: trimmed) {
            return durationMatch
        }

        return ParsedReminderInput(
            title: cleanTitle(trimmed),
            target: .duration(seconds: max(10, fallbackDurationSeconds)),
            matchedExplicitTime: false
        )
    }

    private static func extractClockTime(from input: String, now: Date, calendar: Calendar) -> ParsedReminderInput? {
        let pattern = #"(?:^|\s)(?:(at)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?=\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }

        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        for match in regex.matches(in: input, range: nsRange) {
            let hasColonMinutes = match.range(at: 3).location != NSNotFound
            let hasMeridiem = match.range(at: 4).location != NSNotFound

            // avoid misreading plain numbers like "look at 2" as a clock time
            guard hasColonMinutes || hasMeridiem else { continue }
            guard let hourRange = Range(match.range(at: 2), in: input), var hour = Int(input[hourRange]) else { continue }

            var minute = 0
            if hasColonMinutes, let minRange = Range(match.range(at: 3), in: input) {
                guard let parsedMin = Int(input[minRange]), (0...59).contains(parsedMin) else { continue }
                minute = parsedMin
            }

            if hasMeridiem, let merRange = Range(match.range(at: 4), in: input) {
                let mer = input[merRange].lowercased()
                guard (1...12).contains(hour) else { continue }
                if mer == "pm" && hour < 12 { hour += 12 }
                else if mer == "am" && hour == 12 { hour = 0 }
            } else {
                guard (0...23).contains(hour) else { continue }
            }

            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0

            guard var targetDate = calendar.date(from: comps) else { continue }
            if targetDate.timeIntervalSince(now) <= 5, let nextDay = calendar.date(byAdding: .day, value: 1, to: targetDate) {
                targetDate = nextDay
            }

            let secondsFromNow = max(10, Int(targetDate.timeIntervalSince(now).rounded()))
            guard let fullMatchRange = Range(match.range(at: 0), in: input) else { continue }
            var stripped = input
            stripped.removeSubrange(fullMatchRange)

            return ParsedReminderInput(
                title: cleanTitle(stripped),
                target: .clockTime(targetDate: targetDate, secondsFromNow: secondsFromNow),
                matchedExplicitTime: true
            )
        }

        return nil
    }

    private static func extractExplicitDuration(from input: String) -> ParsedReminderInput? {
        let compoundPattern = #"(?:^|\s)(?:(?:in|for)\s+)?(?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\s*(?:(\d+)\s*(?:m|min|mins|minute|minutes))?|(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes)|(\d+)\s*(?:s|sec|secs|second|seconds))(?=\s|$)"#
        let inBarePattern = #"(?:^|\s)in\s+(\d+(?:\.\d+)?)(?=\s|$)"#

        if let regex = try? NSRegularExpression(pattern: compoundPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
            for match in regex.matches(in: input, range: nsRange) {
                guard let matchRange = Range(match.range(at: 0), in: input) else { continue }
                // only pull durations off the start/end so titles like "review PR 42" stay untouched
                let isBoundary = matchRange.lowerBound == input.startIndex || matchRange.upperBound == input.endIndex
                guard isBoundary else { continue }

                var totalSeconds: Double = 0
                if match.range(at: 1).location != NSNotFound, let hRange = Range(match.range(at: 1), in: input), let hours = Double(input[hRange]) {
                    totalSeconds += hours * 3600.0
                    if match.range(at: 2).location != NSNotFound, let mRange = Range(match.range(at: 2), in: input), let mins = Double(input[mRange]) {
                        totalSeconds += mins * 60.0
                    }
                } else if match.range(at: 3).location != NSNotFound, let mRange = Range(match.range(at: 3), in: input), let mins = Double(input[mRange]) {
                    totalSeconds += mins * 60.0
                } else if match.range(at: 4).location != NSNotFound, let sRange = Range(match.range(at: 4), in: input), let secs = Double(input[sRange]) {
                    totalSeconds += secs
                }

                let clamped = Int(totalSeconds.rounded())
                guard clamped >= 5, clamped <= 24 * 3600 else { continue }

                var stripped = input
                stripped.removeSubrange(matchRange)
                return ParsedReminderInput(title: cleanTitle(stripped), target: .duration(seconds: max(10, clamped)), matchedExplicitTime: true)
            }
        }

        if let regex = try? NSRegularExpression(pattern: inBarePattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
            if let match = regex.firstMatch(in: input, range: nsRange),
               let matchRange = Range(match.range(at: 0), in: input),
               let numRange = Range(match.range(at: 1), in: input),
               let mins = Double(input[numRange]), mins > 0, mins <= 1440 {
                var stripped = input
                stripped.removeSubrange(matchRange)
                return ParsedReminderInput(
                    title: cleanTitle(stripped),
                    target: .duration(seconds: max(10, Int((mins * 60.0).rounded()))),
                    matchedExplicitTime: true
                )
            }
        }

        return nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—:,"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
