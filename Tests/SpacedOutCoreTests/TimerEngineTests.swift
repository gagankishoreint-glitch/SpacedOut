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
final class MockSyncProvider: AppleSyncProviding {
    var createdCount = 0
    var updatedCount = 0
    var completedCount = 0
    var deletedPairs: [(reminderID: String?, calendarEventID: String?)] = []
    var snapshotsByID: [UUID: ExternalSyncSnapshot] = [:]

    func syncCreated(_ reminder: ReminderItem) async -> SyncIdentifiers {
        createdCount += 1
        return SyncIdentifiers(
            reminderID: "ek-rem-\(reminder.id.uuidString)",
            calendarEventID: "ek-cal-\(reminder.id.uuidString)"
        )
    }

    func syncUpdated(_ reminder: ReminderItem) async {
        updatedCount += 1
    }

    func syncCompleted(_ reminder: ReminderItem) async {
        completedCount += 1
    }

    func syncDeleted(reminderID: String?, calendarEventID: String?) async {
        deletedPairs.append((reminderID, calendarEventID))
    }

    func fetchExternalSnapshot(for reminder: ReminderItem) async -> ExternalSyncSnapshot? {
        snapshotsByID[reminder.id]
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

    func testEditTitleDurationAndMultiDayCalendarTargetDate() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())

        let item = engine.createReminder(title: "Old label", durationSeconds: 300)
        let threeDaysLater = clock.now.addingTimeInterval(3 * 86400)
        engine.updateReminder(
            id: item.id,
            title: "Flight check-in",
            targetDate: threeDaysLater,
            accent: .sky
        )

        let updated = engine.activeOrPausedReminders.first
        XCTAssertEqual(updated?.title, "Flight check-in")
        XCTAssertEqual(updated?.accent, .sky)
        XCTAssertEqual(updated?.targetDate.timeIntervalSince1970 ?? 0, threeDaysLater.timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(updated?.durationSeconds, 3 * 86400)
        XCTAssertTrue(engine.activityLog.contains { $0.kind == .edited && $0.reminderTitle == "Flight check-in" })
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
        engine.updateSettings {
            $0.appleRemindersSyncEnabled = true
            $0.appleCalendarSyncEnabled = true
        }

        let item = engine.createReminder(title: "Sync me", durationSeconds: 120)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.createdCount, 1)
        XCTAssertEqual(engine.activeOrPausedReminders.first?.externalReminderID, "ek-rem-\(item.id.uuidString)")
        XCTAssertEqual(engine.activeOrPausedReminders.first?.externalCalendarEventID, "ek-cal-\(item.id.uuidString)")

        engine.updateReminder(id: item.id, title: "Sync me updated")
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.updatedCount, 1)

        engine.completeReminder(id: item.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(mockSync.completedCount, 1)
    }

    func testRestartRecoveryArmsMissedTimersAndLogsOfflineGap() {
        let clock = MutableTestClock()
        let store = InMemoryStateStore()

        let firstEngine = TimerEngine(clock: clock, store: store)
        let overdueWhileOff = firstEngine.createReminder(title: "Take medicine", durationSeconds: 300)
        let stillFuture = firstEngine.createReminder(title: "Evening call", durationSeconds: 7200)

        // simulate Mac shutdown/restart 1 hour later
        clock.advance(by: 3600)
        let rebootedEngine = TimerEngine(clock: clock, store: store)

        XCTAssertEqual(rebootedEngine.triggeredQueue.map(\.id), [overdueWhileOff.id])
        XCTAssertEqual(rebootedEngine.activeOrPausedReminders.map(\.id), [stillFuture.id])
        XCTAssertEqual(rebootedEngine.activeOrPausedReminders.first?.remainingSeconds(at: clock.now) ?? 0, 3600, accuracy: 0.5)

        let recoveryEvents = rebootedEngine.activityLog.filter { $0.kind == .recoveredAfterRestart }
        XCTAssertEqual(recoveryEvents.count, 2)
    }

    func testTwoWayExternalSyncUpdateCompletionAndDeletion() async throws {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())
        let mockSync = MockSyncProvider()
        engine.attachSyncProvider(mockSync)

        let first = engine.createReminder(title: "Dentist", durationSeconds: 3600)
        let second = engine.createReminder(title: "Water plants", durationSeconds: 1800)
        let third = engine.createReminder(title: "Standup", durationSeconds: 2400)
        try await Task.sleep(nanoseconds: 30_000_000)

        // 1. edited in Apple Calendar
        let shiftedDate = clock.now.addingTimeInterval(5400)
        mockSync.snapshotsByID[first.id] = ExternalSyncSnapshot(
            reminderExists: true,
            reminderCompleted: false,
            reminderTitle: "Dentist",
            reminderTargetDate: first.targetDate,
            calendarEventExists: true,
            calendarTitle: "Dentist Visit",
            calendarTargetDate: shiftedDate
        )
        // 2. completed in Apple Reminders
        mockSync.snapshotsByID[second.id] = ExternalSyncSnapshot(
            reminderExists: true,
            reminderCompleted: true,
            reminderTitle: "Water plants",
            reminderTargetDate: second.targetDate,
            calendarEventExists: true,
            calendarTitle: "Water plants",
            calendarTargetDate: second.targetDate
        )
        // 3. deleted externally in Apple Calendar -> should delete surviving Apple Reminder too
        mockSync.snapshotsByID[third.id] = ExternalSyncSnapshot(
            reminderExists: true,
            reminderCompleted: false,
            reminderTitle: "Standup",
            reminderTargetDate: third.targetDate,
            calendarEventExists: false
        )

        await engine.reconcileAllFromSyncProvider()
        try await Task.sleep(nanoseconds: 30_000_000)

        let updatedFirst = engine.activeOrPausedReminders.first { $0.id == first.id }
        XCTAssertEqual(updatedFirst?.title, "Dentist Visit")
        XCTAssertEqual(updatedFirst?.targetDate.timeIntervalSince1970 ?? 0, shiftedDate.timeIntervalSince1970, accuracy: 0.5)

        XCTAssertFalse(engine.reminders.contains { $0.id == second.id })
        XCTAssertEqual(engine.history.first?.title, "Water plants")
        XCTAssertEqual(engine.history.first?.outcome, .completed)

        XCTAssertFalse(engine.reminders.contains { $0.id == third.id })
        XCTAssertTrue(mockSync.deletedPairs.contains { $0.reminderID == "ek-rem-\(third.id.uuidString)" && $0.calendarEventID == nil })
        XCTAssertTrue(engine.activityLog.contains { $0.kind == .externalSyncUpdated })
        XCTAssertTrue(engine.activityLog.contains { $0.kind == .externalSyncDeleted })
    }

    func testWatchdogArmedStateReflectsActiveTimersAndSetting() {
        let clock = MutableTestClock()
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())
        XCTAssertFalse(engine.shouldArmWatchdog)

        let item = engine.createReminder(title: "Focus block", durationSeconds: 600)
        XCTAssertTrue(engine.shouldArmWatchdog)

        engine.updateSettings { $0.accountabilityWatchdogEnabled = false }
        XCTAssertFalse(engine.shouldArmWatchdog)

        engine.updateSettings { $0.accountabilityWatchdogEnabled = true }
        XCTAssertTrue(engine.shouldArmWatchdog)

        engine.deleteReminder(id: item.id)
        XCTAssertFalse(engine.shouldArmWatchdog)
    }

    func testGlassOpacityClampingAllowsSheerToSolid() {
        let engine = TimerEngine(clock: MutableTestClock(), store: InMemoryStateStore())
        XCTAssertEqual(engine.settings.widgetOpacity, 0.78, accuracy: 0.001)

        engine.updateSettings { $0.widgetOpacity = 0.20 }
        XCTAssertEqual(engine.settings.widgetOpacity, 0.20, accuracy: 0.001)

        engine.updateSettings { $0.widgetOpacity = 0.02 }
        XCTAssertEqual(engine.settings.widgetOpacity, 0.15, accuracy: 0.001)

        engine.updateSettings { $0.widgetOpacity = 1.4 }
        XCTAssertEqual(engine.settings.widgetOpacity, 1.0, accuracy: 0.001)
    }

    func testExternalSyncIgnoresReminderSecondTruncationAndPausedDates() async throws {
        let clock = MutableTestClock(Date(timeIntervalSince1970: 1_700_000_027))
        let engine = TimerEngine(clock: clock, store: InMemoryStateStore())
        let mockSync = MockSyncProvider()
        engine.attachSyncProvider(mockSync)

        let active = engine.createReminder(title: "Steep tea", durationSeconds: 240)
        let paused = engine.createReminder(title: "Read paper", durationSeconds: 900)
        try await Task.sleep(nanoseconds: 30_000_000)

        engine.togglePause(id: paused.id)
        try await Task.sleep(nanoseconds: 30_000_000)

        // Apple Reminders strips seconds (:00 -> 27s difference); Apple Calendar keeps exact timestamp
        let truncatedReminderDate = active.targetDate.addingTimeInterval(-27)
        mockSync.snapshotsByID[active.id] = ExternalSyncSnapshot(
            reminderExists: true,
            reminderCompleted: false,
            reminderTitle: "Steep tea",
            reminderTargetDate: truncatedReminderDate,
            calendarEventExists: true,
            calendarTitle: "Steep tea",
            calendarTargetDate: active.targetDate
        )
        // Paused item should sync title change without unpausing or altering remaining seconds
        mockSync.snapshotsByID[paused.id] = ExternalSyncSnapshot(
            reminderExists: true,
            reminderCompleted: false,
            reminderTitle: "Read draft",
            reminderTargetDate: nil,
            calendarEventExists: true,
            calendarTitle: "Read draft",
            calendarTargetDate: paused.targetDate.addingTimeInterval(600)
        )

        let originalTarget = active.targetDate
        await engine.reconcileAllFromSyncProvider()

        let activeAfter = engine.activeOrPausedReminders.first { $0.id == active.id }
        XCTAssertEqual(activeAfter?.targetDate.timeIntervalSince1970 ?? 0, originalTarget.timeIntervalSince1970, accuracy: 0.1)

        let pausedAfter = engine.activeOrPausedReminders.first { $0.id == paused.id }
        XCTAssertEqual(pausedAfter?.status, .paused)
        XCTAssertEqual(pausedAfter?.title, "Read draft")
        XCTAssertEqual(pausedAfter?.pausedRemainingSeconds ?? 0, 900, accuracy: 0.5)
    }

    func testSchemaUpgradeMigratesV1DefaultOpacityWithoutClobberingCustom() {
        let customSettings = AppSettings(widgetOpacity: 0.85)
        let v1DefaultStore = InMemoryStateStore(
            initialState: PersistedState(
                schemaVersion: 1,
                settings: AppSettings(widgetOpacity: 0.94)
            )
        )
        let migrated = TimerEngine(clock: MutableTestClock(), store: v1DefaultStore)
        XCTAssertEqual(migrated.settings.widgetOpacity, 0.78, accuracy: 0.001)

        let v1CustomStore = InMemoryStateStore(
            initialState: PersistedState(
                schemaVersion: 1,
                settings: customSettings
            )
        )
        let preserved = TimerEngine(clock: MutableTestClock(), store: v1CustomStore)
        XCTAssertEqual(preserved.settings.widgetOpacity, 0.85, accuracy: 0.001)
    }
}
