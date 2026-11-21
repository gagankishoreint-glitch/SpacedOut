import XCTest
@testable import SpacedOutCore

final class PersistenceTests: XCTestCase {
    func testAtomicSaveAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacedout-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("state.json")
        let store = AtomicJSONStore(fileURL: storeURL)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reminder = ReminderItem(
            title: "Check laundry",
            durationSeconds: 1800,
            createdAt: now,
            targetDate: now.addingTimeInterval(1800),
            externalReminderID: "rem-1",
            externalCalendarEventID: "cal-1",
            accent: .sky
        )
        let entry = HistoryEntry(
            title: "Steep tea",
            plannedDurationSeconds: 240,
            actualElapsedSeconds: 242,
            createdAt: now.addingTimeInterval(-300),
            finishedAt: now,
            outcome: .completed,
            snoozeCount: 0
        )
        let logEntry = ActivityLogEntry(
            timestamp: now,
            kind: .created,
            reminderID: reminder.id,
            reminderTitle: "Check laundry",
            details: "Scheduled for 30m"
        )
        var settings = AppSettings()
        settings.quickPresetsMinutes = [3, 7, 15, 30]
        settings.displayMode = .menuBarOnly

        let state = PersistedState(
            reminders: [reminder],
            history: [entry],
            activityLog: [logEntry],
            settings: settings,
            lastSeenAt: now
        )

        try store.save(state)
        let loaded = try store.load()
        XCTAssertEqual(loaded, state)
    }

    func testBackwardsCompatibleDecodingWithMissingKeys() throws {
        let partialJSON = """
        {
          "schemaVersion": 1,
          "reminders": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "title": "Legacy timer",
              "durationSeconds": 600,
              "createdAt": "2026-11-21T10:00:00Z",
              "targetDate": "2026-11-21T10:10:00Z"
            }
          ],
          "settings": {
            "themeMode": "dark"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedState.self, from: partialJSON)

        XCTAssertEqual(decoded.settings.themeMode, .dark)
        XCTAssertEqual(decoded.settings.quickPresetsMinutes, [5, 10, 15, 25])
        XCTAssertTrue(decoded.settings.appleRemindersSyncEnabled)
        XCTAssertTrue(decoded.settings.appleCalendarSyncEnabled)
        XCTAssertEqual(decoded.reminders.count, 1)
        XCTAssertEqual(decoded.reminders.first?.title, "Legacy timer")
        XCTAssertNil(decoded.reminders.first?.externalCalendarEventID)
        XCTAssertEqual(decoded.history, [])
        XCTAssertEqual(decoded.activityLog, [])
    }

    func testCorruptFileCreatesBackupAndThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacedout-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("state.json")
        try "{not-valid-json".data(using: .utf8)!.write(to: storeURL)

        let store = AtomicJSONStore(fileURL: storeURL)
        XCTAssertThrowsError(try store.load())

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("state.corrupt.") })
    }
}
