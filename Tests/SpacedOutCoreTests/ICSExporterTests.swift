import XCTest
@testable import SpacedOutCore

final class ICSExporterTests: XCTestCase {
    func testExportsValidICalendarWithEscaping() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reminder = ReminderItem(
            title: "Call Alex, Sam; review\nnotes",
            durationSeconds: 900,
            createdAt: now,
            targetDate: now.addingTimeInterval(900)
        )

        let ics = ICSExporter.export(reminders: [reminder], now: now)
        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("SUMMARY:Call Alex\\, Sam\\; review\\nnotes\r\n"))
        XCTAssertTrue(ics.contains("BEGIN:VALARM\r\n"))
        XCTAssertTrue(ics.contains("END:VCALENDAR\r\n"))
    }
}
