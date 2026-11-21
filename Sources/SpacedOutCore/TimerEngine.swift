import Foundation
import Observation

public protocol ClockProviding: Sendable {
    var now: Date { get }
}

public struct SystemClock: ClockProviding {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public protocol RemindersSyncProviding: AnyObject {
    func syncCreated(_ reminder: ReminderItem) async -> String?
    func syncUpdated(_ reminder: ReminderItem) async
    func syncCompleted(_ reminder: ReminderItem) async
    func syncDeleted(externalID: String) async
}

@MainActor
@Observable
public final class TimerEngine {
    public private(set) var reminders: [ReminderItem] = []
    public private(set) var history: [HistoryEntry] = []
    public private(set) var settings: AppSettings = AppSettings()
    public private(set) var lastPersistenceError: String?

    private let clock: ClockProviding
    private let store: StatePersisting
    private weak var syncProvider: RemindersSyncProviding?

    public var onPreAlert: ((ReminderItem) -> Void)?
    public var onTriggered: (([ReminderItem]) -> Void)?
    public var onSettingsChanged: ((AppSettings) -> Void)?

    public init(
        clock: ClockProviding = SystemClock(),
        store: StatePersisting = AtomicJSONStore(),
        syncProvider: RemindersSyncProviding? = nil
    ) {
        self.clock = clock
        self.store = store
        self.syncProvider = syncProvider
        loadInitialState()
    }

    public func attachSyncProvider(_ provider: RemindersSyncProviding?) {
        self.syncProvider = provider
    }

    // MARK: - Derived Collections

    public var activeOrPausedReminders: [ReminderItem] {
        reminders
            .filter { $0.status == .active || $0.status == .paused }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status == .active
                }
                return lhs.targetDate < rhs.targetDate
            }
    }

    public var triggeredQueue: [ReminderItem] {
        reminders
            .filter { $0.status == .triggered }
            .sorted { $0.targetDate < $1.targetDate }
    }

    public var earliestActiveReminder: ReminderItem? {
        reminders
            .filter { $0.status == .active }
            .min { $0.targetDate < $1.targetDate }
    }

    public var currentPreAlertReminder: ReminderItem? {
        guard settings.notificationStyle == .fullScreenWithPreAlert else { return nil }
        let now = clock.now
        let window = TimeInterval(settings.preAlertSeconds)
        return reminders
            .filter { $0.status == .active }
            .filter {
                let rem = $0.remainingSeconds(at: now)
                return rem > 0 && rem <= window
            }
            .min { $0.targetDate < $1.targetDate }
    }

    // MARK: - Creation

    @discardableResult
    public func createFromQuickInput(
        _ rawInput: String,
        fallbackDurationSeconds: Int? = nil,
        accent: AccentPreset = .mint
    ) -> ReminderItem {
        let now = clock.now
        let fallback = fallbackDurationSeconds ?? (settings.defaultDurationMinutes * 60)
        let parsed = QuickInputParser.parse(rawInput, now: now, fallbackDurationSeconds: fallback)

        switch parsed.target {
        case .duration(let seconds):
            return createReminder(title: parsed.title, durationSeconds: seconds, accent: accent)
        case .clockTime(let targetDate, let secondsFromNow):
            return createReminder(
                title: parsed.title,
                durationSeconds: secondsFromNow,
                targetDate: targetDate,
                accent: accent
            )
        }
    }

    @discardableResult
    public func createReminder(
        title: String,
        durationSeconds: Int,
        targetDate: Date? = nil,
        accent: AccentPreset = .mint
    ) -> ReminderItem {
        let now = clock.now
        let clampedDuration = max(5, min(24 * 3600, durationSeconds))
        let resolvedTarget = targetDate ?? now.addingTimeInterval(TimeInterval(clampedDuration))

        let item = ReminderItem(
            title: title,
            durationSeconds: clampedDuration,
            createdAt: now,
            startedAt: now,
            targetDate: resolvedTarget,
            status: .active,
            accent: accent
        )

        reminders.append(item)
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            let itemID = item.id
            Task { @MainActor [weak self] in
                guard let extID = await syncProvider.syncCreated(item) else { return }
                self?.setExternalReminderID(extID, for: itemID)
            }
        }

        return item
    }

    // MARK: - Editing & Lifecycle

    public func updateReminder(id: UUID, title: String? = nil, durationSeconds: Int? = nil) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders[idx]
        let now = clock.now

        if let title {
            item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let durationSeconds {
            let clamped = max(10, min(24 * 3600, durationSeconds))
            item.durationSeconds = clamped
            if item.status == .paused {
                item.pausedRemainingSeconds = TimeInterval(clamped)
            } else if item.status == .active {
                item.startedAt = now
                item.targetDate = now.addingTimeInterval(TimeInterval(clamped))
                item.preAlertSent = false
            }
        }

        reminders[idx] = item
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func adjustRemaining(id: UUID, deltaSeconds: Int) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders[idx]
        let now = clock.now

        switch item.status {
        case .active:
            let currentRem = item.remainingSeconds(at: now)
            let nextRem = max(10, min(24 * 3600, currentRem + TimeInterval(deltaSeconds)))
            item.targetDate = now.addingTimeInterval(nextRem)
            if Int(nextRem.rounded()) > item.durationSeconds {
                item.durationSeconds = Int(nextRem.rounded())
            }
            if nextRem > TimeInterval(settings.preAlertSeconds) {
                item.preAlertSent = false
            }
        case .paused:
            let currentRem = item.pausedRemainingSeconds ?? TimeInterval(item.durationSeconds)
            let nextRem = max(10, min(24 * 3600, currentRem + TimeInterval(deltaSeconds)))
            item.pausedRemainingSeconds = nextRem
            if Int(nextRem.rounded()) > item.durationSeconds {
                item.durationSeconds = Int(nextRem.rounded())
            }
        case .triggered, .completed, .dismissed:
            return
        }

        reminders[idx] = item
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func togglePause(id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders[idx]
        let now = clock.now

        if item.status == .active {
            let rem = max(1, item.targetDate.timeIntervalSince(now))
            item.pausedRemainingSeconds = rem
            item.status = .paused
        } else if item.status == .paused {
            let rem = max(1, item.pausedRemainingSeconds ?? TimeInterval(item.durationSeconds))
            item.targetDate = now.addingTimeInterval(rem)
            item.pausedRemainingSeconds = nil
            item.status = .active
        } else {
            return
        }

        reminders[idx] = item
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func deleteReminder(id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        let removed = reminders.remove(at: idx)
        persistState()

        if settings.appleRemindersSyncEnabled,
           let extID = removed.externalReminderID,
           let syncProvider {
            Task { @MainActor in
                await syncProvider.syncDeleted(externalID: extID)
            }
        }
    }

    // MARK: - Trigger Evaluation & Alert Resolution

    @discardableResult
    public func evaluateDueReminders() -> [ReminderItem] {
        let now = clock.now
        var newlyTriggered: [ReminderItem] = []
        var preAlerts: [ReminderItem] = []
        var didMutate = false

        for idx in reminders.indices {
            guard reminders[idx].status == .active else { continue }
            let remaining = reminders[idx].targetDate.timeIntervalSince(now)

            if remaining <= 0 {
                reminders[idx].status = .triggered
                newlyTriggered.append(reminders[idx])
                didMutate = true
            } else if settings.notificationStyle == .fullScreenWithPreAlert,
                      !reminders[idx].preAlertSent,
                      remaining <= TimeInterval(settings.preAlertSeconds) {
                reminders[idx].preAlertSent = true
                preAlerts.append(reminders[idx])
                didMutate = true
            }
        }

        if didMutate {
            persistState()
        }

        for item in preAlerts {
            onPreAlert?(item)
        }

        if !newlyTriggered.isEmpty {
            onTriggered?(newlyTriggered)
        }

        return newlyTriggered
    }

    public func snoozeReminder(id: UUID, addedSeconds: Int) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        let now = clock.now
        let clamped = max(10, min(24 * 3600, addedSeconds))

        var item = reminders[idx]
        item.status = .active
        item.targetDate = now.addingTimeInterval(TimeInterval(clamped))
        item.durationSeconds = clamped
        item.pausedRemainingSeconds = nil
        item.snoozeCount += 1
        item.totalSnoozedSeconds += clamped
        item.preAlertSent = false

        reminders[idx] = item
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func completeReminder(id: UUID) {
        archiveReminder(id: id, outcome: .completed)
    }

    public func dismissReminder(id: UUID) {
        archiveReminder(id: id, outcome: .dismissed)
    }

    private func archiveReminder(id: UUID, outcome: HistoryOutcome) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders.remove(at: idx)
        let now = clock.now
        item.status = outcome == .completed ? .completed : .dismissed
        item.completedAt = now

        let actualElapsed = max(0, Int(now.timeIntervalSince(item.createdAt).rounded()))
        let entry = HistoryEntry(
            title: item.title,
            plannedDurationSeconds: item.durationSeconds,
            actualElapsedSeconds: actualElapsed,
            createdAt: item.createdAt,
            finishedAt: now,
            outcome: outcome,
            snoozeCount: item.snoozeCount,
            accent: item.accent
        )

        history.insert(entry, at: 0)
        persistState()

        if settings.appleRemindersSyncEnabled, let syncProvider {
            if outcome == .completed {
                Task { @MainActor in
                    await syncProvider.syncCompleted(item)
                }
            } else if let extID = item.externalReminderID {
                Task { @MainActor in
                    await syncProvider.syncDeleted(externalID: extID)
                }
            }
        }
    }

    // MARK: - History & Stats

    @discardableResult
    public func rerunHistoryEntry(_ entry: HistoryEntry) -> ReminderItem {
        createReminder(
            title: entry.title,
            durationSeconds: entry.plannedDurationSeconds,
            accent: entry.accent
        )
    }

    public func deleteHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        persistState()
    }

    public func clearHistory() {
        history.removeAll()
        persistState()
    }

    public func dailyStats(for date: Date? = nil, calendar: Calendar = .current) -> DailyFocusStats {
        let ref = date ?? clock.now
        let todaysEntries = history.filter { calendar.isDate($0.finishedAt, inSameDayAs: ref) }
        let completed = todaysEntries.filter { $0.outcome == .completed }
        let dismissed = todaysEntries.filter { $0.outcome == .dismissed }
        let totalMinutes = completed.reduce(0) { $0 + max(1, $1.plannedDurationSeconds / 60) }
        let onTime = completed.filter { $0.snoozeCount == 0 }.count

        return DailyFocusStats(
            completedCount: completed.count,
            dismissedCount: dismissed.count,
            totalFocusMinutes: totalMinutes,
            onTimeCount: onTime
        )
    }

    // MARK: - Settings & Persistence

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        settings.widgetOpacity = min(1.0, max(0.72, settings.widgetOpacity))
        settings.preAlertSeconds = max(10, min(120, settings.preAlertSeconds))
        settings.defaultDurationMinutes = max(1, min(999, settings.defaultDurationMinutes))
        if settings.quickPresetsMinutes.isEmpty {
            settings.quickPresetsMinutes = [5, 10, 15, 25]
        } else {
            settings.quickPresetsMinutes = settings.quickPresetsMinutes.map { max(1, min(999, $0)) }
        }
        persistState()
        onSettingsChanged?(settings)
    }

    public func setExternalReminderID(_ externalID: String, for id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].externalReminderID = externalID
        persistState()
    }

    public func resetAllData() {
        reminders.removeAll()
        history.removeAll()
        settings = AppSettings()
        persistState()
        onSettingsChanged?(settings)
    }

    private func loadInitialState() {
        do {
            let loaded = try store.load()
            self.reminders = loaded.reminders.filter {
                $0.status == .active || $0.status == .paused || $0.status == .triggered
            }
            self.history = loaded.history.sorted { $0.finishedAt > $1.finishedAt }
            self.settings = loaded.settings
            self.lastPersistenceError = nil
        } catch {
            self.reminders = []
            self.history = []
            self.settings = AppSettings()
            self.lastPersistenceError = error.localizedDescription
        }
    }

    private func persistState() {
        let snapshot = PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            reminders: reminders,
            history: history,
            settings: settings
        )
        do {
            try store.save(snapshot)
            self.lastPersistenceError = nil
        } catch {
            self.lastPersistenceError = error.localizedDescription
        }
    }
}
