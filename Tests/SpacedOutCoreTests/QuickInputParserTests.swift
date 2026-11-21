import XCTest
@testable import SpacedOutCore

final class QuickInputParserTests: XCTestCase {
    private var fixedCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(year: Int = 2026, month: Int = 11, day: Int = 21, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return fixedCalendar.date(from: comps)!
    }

    func testParsesDurationSuffixAndPrefix() {
        let now = makeDate(hour: 10, minute: 0)

        let suffix = QuickInputParser.parse("tea 4m", now: now, calendar: fixedCalendar)
        XCTAssertEqual(suffix.title, "tea")
        XCTAssertEqual(suffix.target, .duration(seconds: 240))
        XCTAssertTrue(suffix.matchedExplicitTime)

        let prefix = QuickInputParser.parse("15min stretch back", now: now, calendar: fixedCalendar)
        XCTAssertEqual(prefix.title, "stretch back")
        XCTAssertEqual(prefix.target, .duration(seconds: 900))
        XCTAssertTrue(prefix.matchedExplicitTime)
    }

    func testParsesCompoundHoursAndMinutes() {
        let now = makeDate(hour: 10, minute: 0)

        let compound = QuickInputParser.parse("1h30m deep work", now: now, calendar: fixedCalendar)
        XCTAssertEqual(compound.title, "deep work")
        XCTAssertEqual(compound.target, .duration(seconds: 5400))

        let spaced = QuickInputParser.parse("review architecture for 1h 15m", now: now, calendar: fixedCalendar)
        XCTAssertEqual(spaced.title, "review architecture")
        XCTAssertEqual(spaced.target, .duration(seconds: 4500))
    }

    func testParsesSecondsAndInPreposition() {
        let now = makeDate(hour: 10, minute: 0)

        let secs = QuickInputParser.parse("plank 45s", now: now, calendar: fixedCalendar)
        XCTAssertEqual(secs.title, "plank")
        XCTAssertEqual(secs.target, .duration(seconds: 45))

        let bareIn = QuickInputParser.parse("check oven in 12", now: now, calendar: fixedCalendar)
        XCTAssertEqual(bareIn.title, "check oven")
        XCTAssertEqual(bareIn.target, .duration(seconds: 720))
    }

    func testParsesBareNumberBeyond99Minutes() {
        let now = makeDate(hour: 10, minute: 0)
        let parsed = QuickInputParser.parse("150", now: now, calendar: fixedCalendar)
        XCTAssertEqual(parsed.title, "")
        XCTAssertEqual(parsed.target, .duration(seconds: 9000))
    }

    func testDoesNotMisinterpretNumbersEmbeddedInTitle() {
        let now = makeDate(hour: 10, minute: 0)
        let parsed = QuickInputParser.parse("Review PR 42", now: now, fallbackDurationSeconds: 600, calendar: fixedCalendar)
        XCTAssertEqual(parsed.title, "Review PR 42")
        XCTAssertEqual(parsed.target, .duration(seconds: 600))
        XCTAssertFalse(parsed.matchedExplicitTime)
    }

    func testParses12HourClockTimeSameDayAndRollover() {
        let morning = makeDate(hour: 10, minute: 0)
        let afternoonCall = QuickInputParser.parse("call Sam at 4:30pm", now: morning, calendar: fixedCalendar)
        XCTAssertEqual(afternoonCall.title, "call Sam")
        XCTAssertEqual(
            afternoonCall.target,
            .clockTime(targetDate: makeDate(hour: 16, minute: 30), secondsFromNow: 6 * 3600 + 30 * 60)
        )

        let evening = makeDate(hour: 18, minute: 0)
        let rollover = QuickInputParser.parse("5pm wrap up", now: evening, calendar: fixedCalendar)
        XCTAssertEqual(rollover.title, "wrap up")
        XCTAssertEqual(
            rollover.target,
            .clockTime(targetDate: makeDate(day: 22, hour: 17, minute: 0), secondsFromNow: 23 * 3600)
        )
    }

    func testParses24HourClockTime() {
        let morning = makeDate(hour: 9, minute: 0)
        let standup = QuickInputParser.parse("at 16:45 standup", now: morning, calendar: fixedCalendar)
        XCTAssertEqual(standup.title, "standup")
        XCTAssertEqual(
            standup.target,
            .clockTime(targetDate: makeDate(hour: 16, minute: 45), secondsFromNow: 7 * 3600 + 45 * 60)
        )
    }

    func testParsesCalendarDateExpressions() {
        // 2026-11-21 10:00 UTC is a Saturday
        let now = makeDate(year: 2026, month: 11, day: 21, hour: 10, minute: 0)

        let tomorrow = QuickInputParser.parse("dentist tomorrow 9am", now: now, calendar: fixedCalendar)
        XCTAssertEqual(tomorrow.title, "dentist")
        XCTAssertEqual(
            tomorrow.target,
            .clockTime(targetDate: makeDate(year: 2026, month: 11, day: 22, hour: 9, minute: 0), secondsFromNow: 23 * 3600)
        )

        let monthDay = QuickInputParser.parse("demo nov 25 at 2:30pm", now: now, calendar: fixedCalendar)
        XCTAssertEqual(monthDay.title, "demo")
        XCTAssertEqual(
            monthDay.target,
            .clockTime(targetDate: makeDate(year: 2026, month: 11, day: 25, hour: 14, minute: 30), secondsFromNow: 4 * 86400 + 4 * 3600 + 1800)
        )

        let weekday = QuickInputParser.parse("mon 8:15am sync", now: now, calendar: fixedCalendar)
        XCTAssertEqual(weekday.title, "sync")
        XCTAssertEqual(
            weekday.target,
            .clockTime(targetDate: makeDate(year: 2026, month: 11, day: 23, hour: 8, minute: 15), secondsFromNow: 2 * 86400 - 3600 - 2700)
        )

        let slashDate = QuickInputParser.parse("12/01 14:00 pay rent", now: now, calendar: fixedCalendar)
        XCTAssertEqual(slashDate.title, "pay rent")
        XCTAssertEqual(
            slashDate.target,
            .clockTime(targetDate: makeDate(year: 2026, month: 12, day: 1, hour: 14, minute: 0), secondsFromNow: 10 * 86400 + 4 * 3600)
        )
    }
}
