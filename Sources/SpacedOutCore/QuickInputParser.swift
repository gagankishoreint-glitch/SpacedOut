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
            return "\(Self.humanDuration(seconds)) · \(Self.formatTarget(targetDate, relativeTo: now, calendar: calendar))"
        case .clockTime(let date, let secondsFromNow):
            let prefix = calendar.isDate(date, inSameDayAs: now) ? "At " : ""
            return "\(prefix)\(Self.formatTarget(date, relativeTo: now, calendar: calendar)) · in \(Self.humanDuration(secondsFromNow))"
        }
    }

    private static func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds >= 86400 {
            let days = seconds / 86400
            let hrs = (seconds % 86400) / 3600
            return hrs > 0 ? "\(days)d \(hrs)h" : "\(days)d"
        }
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let remSec = seconds % 60
        if hrs > 0 && mins > 0 { return "\(hrs)h \(mins)m" }
        if hrs > 0 { return "\(hrs)h" }
        if remSec > 0 { return "\(mins)m \(remSec)s" }
        return "\(mins)m"
    }

    private static func formatTarget(_ date: Date, relativeTo now: Date, calendar: Calendar) -> String {
        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.locale = Locale.current
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        let timePart = timeFmt.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return timePart
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(timePart)"
        }
        let dateFmt = DateFormatter()
        dateFmt.calendar = calendar
        dateFmt.locale = Locale.current
        dateFmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(dateFmt.string(from: date)) \(timePart)"
    }
}

public enum QuickInputParser {
    private static let monthMap: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6,
        "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    // Calendar.weekday: 1=Sun ... 7=Sat
    private static let weekdayMap: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7
    ]

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

        if let calendarMatch = extractCalendarDateTime(from: trimmed, now: now, calendar: calendar) {
            return calendarMatch
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

    private static func extractCalendarDateTime(from input: String, now: Date, calendar: Calendar) -> ParsedReminderInput? {
        let timeClause = #"(?:(?:at)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#

        // 1. ISO / numeric date + time: "2026-11-25 14:30" or "11/25 at 4:30pm"
        let isoPattern = #"(?:^|\s)(?:on\s+)?(\d{4})-(\d{1,2})-(\d{1,2})\s+"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(isoPattern, in: input),
           let y = intGroup(1, match, input), let m = intGroup(2, match, input), let d = intGroup(3, match, input),
           let (hour, minute) = parseTimeGroups(hourIdx: 4, minIdx: 5, merIdx: 6, match: match, input: input) {
            var comps = DateComponents(year: y, month: m, day: d, hour: hour, minute: minute, second: 0)
            comps.calendar = calendar
            if let date = calendar.date(from: comps), date.timeIntervalSince(now) > 5 {
                return buildDateMatch(input: input, match: match, targetDate: date, now: now)
            }
        }

        let slashPattern = #"(?:^|\s)(?:on\s+)?(\d{1,2})/(\d{1,2})\s+"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(slashPattern, in: input),
           let m = intGroup(1, match, input), let d = intGroup(2, match, input),
           (1...12).contains(m), (1...31).contains(d),
           let (hour, minute) = parseTimeGroups(hourIdx: 3, minIdx: 4, merIdx: 5, match: match, input: input) {
            if let date = resolveUpcomingMonthDay(month: m, day: d, hour: hour, minute: minute, now: now, calendar: calendar) {
                return buildDateMatch(input: input, match: match, targetDate: date, now: now)
            }
        }

        // 2. Named month + day + time: "nov 25 2:30pm" or "25 nov at 9am"
        let monthNames = monthMap.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let monthDayPattern = #"(?:^|\s)(?:on\s+)?("# + monthNames + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,\s*|\s+)"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(monthDayPattern, in: input),
           let mName = stringGroup(1, match, input)?.lowercased(),
           let m = monthMap[mName],
           let d = intGroup(2, match, input), (1...31).contains(d),
           let (hour, minute) = parseTimeGroups(hourIdx: 3, minIdx: 4, merIdx: 5, match: match, input: input) {
            if let date = resolveUpcomingMonthDay(month: m, day: d, hour: hour, minute: minute, now: now, calendar: calendar) {
                return buildDateMatch(input: input, match: match, targetDate: date, now: now)
            }
        }

        let dayMonthPattern = #"(?:^|\s)(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthNames + #")\s+"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(dayMonthPattern, in: input),
           let d = intGroup(1, match, input), (1...31).contains(d),
           let mName = stringGroup(2, match, input)?.lowercased(),
           let m = monthMap[mName],
           let (hour, minute) = parseTimeGroups(hourIdx: 3, minIdx: 4, merIdx: 5, match: match, input: input) {
            if let date = resolveUpcomingMonthDay(month: m, day: d, hour: hour, minute: minute, now: now, calendar: calendar) {
                return buildDateMatch(input: input, match: match, targetDate: date, now: now)
            }
        }

        // 3. Relative day ("today", "tomorrow", "tmrw") + time
        let relPattern = #"(?:^|\s)(today|tomorrow|tmrw)\s+"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(relPattern, in: input),
           let keyword = stringGroup(1, match, input)?.lowercased(),
           let (hour, minute) = parseTimeGroups(hourIdx: 2, minIdx: 3, merIdx: 4, match: match, input: input) {
            let dayOffset = keyword == "today" ? 0 : 1
            if let baseDay = calendar.date(byAdding: .day, value: dayOffset, to: now) {
                var comps = calendar.dateComponents([.year, .month, .day], from: baseDay)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                if var date = calendar.date(from: comps) {
                    if keyword == "today" && date.timeIntervalSince(now) <= 5 {
                        date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                    }
                    if date.timeIntervalSince(now) > 5 {
                        return buildDateMatch(input: input, match: match, targetDate: date, now: now)
                    }
                }
            }
        }

        // 4. Weekday ("mon", "next friday") + time
        let weekdayNames = weekdayMap.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let weekdayPattern = #"(?:^|\s)(?:(on|next)\s+)?("# + weekdayNames + #")\s+"# + timeClause + #"(?=\s|$)"#
        if let match = firstRegexMatch(weekdayPattern, in: input),
           let dayToken = stringGroup(2, match, input)?.lowercased(),
           let targetWeekday = weekdayMap[dayToken],
           let (hour, minute) = parseTimeGroups(hourIdx: 3, minIdx: 4, merIdx: 5, match: match, input: input) {
            let forceNextWeek = stringGroup(1, match, input)?.lowercased() == "next"
            let currentWeekday = calendar.component(.weekday, from: now)
            var daysAhead = (targetWeekday - currentWeekday + 7) % 7
            if forceNextWeek && daysAhead == 0 {
                daysAhead = 7
            }
            if let candidateDay = calendar.date(byAdding: .day, value: daysAhead, to: now) {
                var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                if var date = calendar.date(from: comps) {
                    if date.timeIntervalSince(now) <= 5 {
                        date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
                    }
                    return buildDateMatch(input: input, match: match, targetDate: date, now: now)
                }
            }
        }

        return nil
    }

    private static func resolveUpcomingMonthDay(
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let currentYear = calendar.component(.year, from: now)
        for yearOffset in 0...1 {
            var comps = DateComponents(year: currentYear + yearOffset, month: month, day: day, hour: hour, minute: minute, second: 0)
            comps.calendar = calendar
            if let date = calendar.date(from: comps),
               calendar.component(.month, from: date) == month,
               calendar.component(.day, from: date) == day,
               date.timeIntervalSince(now) > 5 {
                return date
            }
        }
        return nil
    }

    private static func buildDateMatch(input: String, match: NSTextCheckingResult, targetDate: Date, now: Date) -> ParsedReminderInput? {
        guard let range = Range(match.range(at: 0), in: input) else { return nil }
        var stripped = input
        stripped.removeSubrange(range)
        let secondsFromNow = max(10, Int(targetDate.timeIntervalSince(now).rounded()))
        return ParsedReminderInput(
            title: cleanTitle(stripped),
            target: .clockTime(targetDate: targetDate, secondsFromNow: secondsFromNow),
            matchedExplicitTime: true
        )
    }

    private static func parseTimeGroups(
        hourIdx: Int,
        minIdx: Int,
        merIdx: Int,
        match: NSTextCheckingResult,
        input: String
    ) -> (Int, Int)? {
        let hasColon = match.range(at: minIdx).location != NSNotFound
        let hasMeridiem = match.range(at: merIdx).location != NSNotFound
        guard hasColon || hasMeridiem else { return nil }
        guard var hour = intGroup(hourIdx, match, input) else { return nil }

        var minute = 0
        if hasColon {
            guard let parsedMin = intGroup(minIdx, match, input), (0...59).contains(parsedMin) else { return nil }
            minute = parsedMin
        }

        if hasMeridiem, let mer = stringGroup(merIdx, match, input)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            if mer == "pm" && hour < 12 { hour += 12 }
            else if mer == "am" && hour == 12 { hour = 0 }
        } else {
            guard (0...23).contains(hour) else { return nil }
        }
        return (hour, minute)
    }

    private static func firstRegexMatch(_ pattern: String, in input: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, range: nsRange)
    }

    private static func stringGroup(_ idx: Int, _ match: NSTextCheckingResult, _ input: String) -> String? {
        guard idx < match.numberOfRanges, match.range(at: idx).location != NSNotFound,
              let range = Range(match.range(at: idx), in: input) else { return nil }
        return String(input[range])
    }

    private static func intGroup(_ idx: Int, _ match: NSTextCheckingResult, _ input: String) -> Int? {
        guard let s = stringGroup(idx, match, input) else { return nil }
        return Int(s)
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
            guard let (hour, minute) = parseTimeGroups(hourIdx: 2, minIdx: 3, merIdx: 4, match: match, input: input) else { continue }

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
