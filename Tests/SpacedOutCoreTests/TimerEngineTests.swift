import XCTest
@testable import SpacedOutCore

final class MutableTestClock: ClockProviding, @unchecked Sendable {
    var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    var now: Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

@MainActor
final class MockSyncProvider: RemindersSyncProviding {
    var createdCount = 0
    var updatedCount = 0
    var completedCount = 0
    var deletedIDs: [String] = []

    func syncCreated(_ reminder: ReminderItem) async -> String? {
        createdCount += 1
        return "ek-\(reminder.id.uuidString)"
    }

    func syncUpdated(_ reminder: ReminderItem) async {
        updatedCount += 1
    }

    func syncCompleted(_ reminder: ReminderItem) async {
        completedCount += 1
    }

    func syncDeleted(externalID: String) async {
        deletedIDs.append(externalID)
    }
}

@MainActor
final class TimerEngineTests: XCTestCase {
    func testZeroDriftAcrossSimulatedSleepWakeJump() {
        let clock = MutableTestClock()
        let store = InMemoryStateStore()
        let engine = TimerEngine(clock: clock, store: store)

        let item = engine.createReminder(title: "Turn off kettle", durationSeconds: 300)
        XCTAssertEqual(item.remainingSeconds(at: clock.now), 300, accuracy: 0.01)

        clock.advance(by: 295)
        XCTAssertEqual(engine.evaluateDueReminders().count, 0)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.remainingSeconds(at: clock.now) ?? -1, 5, accuracy: 0.01)

        clock.advance(by: 6)
        let triggered = engine.evaluateDueReminders()
        XCTAssertEqual(triggered.count, 1)
        XCTAssertEqual(triggered.first?.id, item.id)
        XCTAssertEqual(engine.triggeredQueue.count, 1)
    }

    func testPauseAndResumePreservesExactRemainingTime() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())

        let item = engine.createReminder(title: "Focus sprint", durationSeconds: 600)
        clock.advance(by: 120)
        engine.togglePause(id: item.id)

        XCTAssertEqual(engine.activeOrPausedReminders.first?.status, .paused)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.remainingSeconds(at: clock.now) ?? 0, 480, accuracy: 0.01)

        // shouldn't tick while paused
        clock.advance(by: 1800)
        XCTAssertEqual(engine.evaluateDueReminders().count, 0)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.remainingSeconds(at: clock.now) ?? 0, 480, accuracy: 0.01)

        engine.togglePause(id: item.id)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.status, .active)
        clock.advance(by: 479)
        XCTAssertEqual(engine.evaluateDueReminders().count, 0)
        clock.advance(by: 2)
        XCTAssertEqual(engine.evaluateDueReminders().count, 1)
    }

    func testEditAndAdjustActiveReminder() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())

        let item = engine.createReminder(title: "Old label", durationSeconds: 300)
        engine.updateReminder(id: item.id, title: "Updated label")
        engine.adjustRemaining(id: item.id, deltaSeconds: 120)

        let updated = engine.activeOrPausedReminders.first
        XCTAssertEqual(updated?.title, "Updated label")
        XCTAssertEqual(updated?.remainingSeconds(at: clock.now) ?? 0, 420, accuracy: 0.01)
    }

    func testPreAlertFiresOnceBeforeFullScreenTrigger() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())
        engine.updateSettings {
            $0.notificationStyle = .fullScreenWithPreAlert
            $0.preAlertSeconds = 30
        }

        var preAlerts: [UUID] = []
        engine.onPreAlert = { preAlerts.append($0.id) }

        let item = engine.createReminder(title: "Join standup", durationSeconds: 120)

        clock.advance(by: 95)
        engine.evaluateDueReminders()
        XCTAssertEqual(preAlerts, [item.id])

        clock.advance(by: 5) // still inside 30s window, shouldn't fire twice
        engine.evaluateDueReminders()
        XCTAssertEqual(preAlerts, [item.id])

        clock.advance(by: 25)
        let triggered = engine.evaluateDueReminders()
        XCTAssertEqual(triggered.map(\.id), [item.id])
    }

    func testSnoozeAndCompleteRecordsHistoryAndStats() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())

        let first = engine.createReminder(title: "Drink water", durationSeconds: 300)
        clock.advance(by: 301)
        _ = engine.evaluateDueReminders()
        XCTAssertEqual(engine.triggeredQueue.count, 1)

        engine.snoozeReminder(id: first.id, addedSeconds: 300)
        XCTAssertEqual(engine.triggeredQueue.count, 0)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.snoozeCount, 1)

        clock.advance(by: 301)
        _ = engine.evaluateDueReminders()
        engine.completeReminder(id: first.id)

        XCTAssertTrue(engine.activeOrPausedReminders.isEmpty)
        XCTAssertTrue(engine.triggeredQueue.isEmpty)
        XCTAssertEqual(engine.history.count, 1)
        XCTAssertEqual(engine.history.first?.outcome, .completed)
        XCTAssertEqual(engine.history.first?.snoozeCount, 1)

        let second = engine.createReminder(title: "Stretch", durationSeconds: 600)
        clock.advance(by: 601)
        _ = engine.evaluateDueReminders()
        engine.completeReminder(id: second.id)

        let stats = engine.dailyStats()
        XCTAssertEqual(stats.completedCount, 2)
        XCTAssertEqual(stats.onTimeCount, 1)
        XCTAssertEqual(stats.onTimePercentage, 50)
    }

    func testSyncProviderHooksCalledWhenEnabled() async throws {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())
        let mockSync = MockSyncProvider()
        engine.attachSyncProvider(mockSync)
        engine.updateSettings { $0.appleRemindersSyncEnabled = true }

        let item = engine.createReminder(title: "Sync me", durationSeconds: 120)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.createdCount, 1)

        engine.updateReminder(id: item.id, title: "Sync me updated")
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.updatedCount, 1)

        engine.completeReminder(id: item.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.completedCount, 1)
    }
}
