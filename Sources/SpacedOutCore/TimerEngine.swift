import Foundation
import Observation

public protocol ClockProviding: Sendable {
    var now: Date { get }
}

public struct SystemClock: ClockProviding {
    public init() {}
    public var now: Date { Date() }
}

public struct SyncIdentifiers: Equatable, Sendable {
    public var reminderID: String?
    public var calendarEventID: String?

    public init(reminderID: String? = nil, calendarEventID: String? = nil) {
        self.reminderID = reminderID
        self.calendarEventID = calendarEventID
    }
}

public struct ExternalSyncSnapshot: Equatable, Sendable {
    public var reminderExists: Bool?
    public var reminderCompleted: Bool
    public var reminderTitle: String?
    public var reminderTargetDate: Date?
    public var calendarEventExists: Bool?
    public var calendarTitle: String?
    public var calendarTargetDate: Date?

    public init(
        reminderExists: Bool? = nil,
        reminderCompleted: Bool = false,
        reminderTitle: String? = nil,
        reminderTargetDate: Date? = nil,
        calendarEventExists: Bool? = nil,
        calendarTitle: String? = nil,
        calendarTargetDate: Date? = nil
    ) {
        self.reminderExists = reminderExists
        self.reminderCompleted = reminderCompleted
        self.reminderTitle = reminderTitle
        self.reminderTargetDate = reminderTargetDate
        self.calendarEventExists = calendarEventExists
        self.calendarTitle = calendarTitle
        self.calendarTargetDate = calendarTargetDate
    }
}

@MainActor
public protocol AppleSyncProviding: AnyObject {
    func syncCreated(_ reminder: ReminderItem) async -> SyncIdentifiers
    func syncUpdated(_ reminder: ReminderItem) async
    func syncCompleted(_ reminder: ReminderItem) async
    func syncDeleted(reminderID: String?, calendarEventID: String?) async
    func fetchExternalSnapshot(for reminder: ReminderItem) async -> ExternalSyncSnapshot?
}

public typealias RemindersSyncProviding = AppleSyncProviding

@MainActor
@Observable
public final class TimerEngine {
    public private(set) var reminders: [ReminderItem] = []
    public private(set) var history: [HistoryEntry] = []
    public private(set) var activityLog: [ActivityLogEntry] = []
    public private(set) var settings: AppSettings = AppSettings()
    public private(set) var lastPersistenceError: String?

    private let clock: ClockProviding
    private let store: StatePersisting
    private weak var syncProvider: AppleSyncProviding?
    private var lastSeenAt: Date?

    public var onPreAlert: ((ReminderItem) -> Void)?
    public var onTriggered: (([ReminderItem]) -> Void)?
    public var onSettingsChanged: ((AppSettings) -> Void)?
    public var onRemindersChanged: (() -> Void)?

    private static let maxDurationSeconds = 365 * 86400
    private static let maxActivityLogEntries = 1500

    public init(
        clock: ClockProviding = SystemClock(),
        store: StatePersisting = AtomicJSONStore(),
        syncProvider: AppleSyncProviding? = nil
    ) {
        self.clock = clock
        self.store = store
        self.syncProvider = syncProvider
        loadInitialState()
    }

    public func attachSyncProvider(_ provider: AppleSyncProviding?) {
        self.syncProvider = provider
    }

    public var isAnyAppleSyncEnabled: Bool {
        settings.appleRemindersSyncEnabled || settings.appleCalendarSyncEnabled
    }

    public var shouldArmWatchdog: Bool {
        settings.accountabilityWatchdogEnabled
            && (!activeOrPausedReminders.isEmpty || !triggeredQueue.isEmpty)
    }

    public var activeOrPausedReminders: [ReminderItem] {
        reminders
            .filter { $0.status == .active || $0.status == .paused }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .active }
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
            return createReminder(title: parsed.title, durationSeconds: secondsFromNow, targetDate: targetDate, accent: accent)
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
        let resolvedTarget: Date
        let resolvedDuration: Int
        if let targetDate {
            let delta = Int(targetDate.timeIntervalSince(now).rounded())
            resolvedDuration = max(5, min(Self.maxDurationSeconds, delta))
            resolvedTarget = max(now.addingTimeInterval(5), targetDate)
        } else {
            resolvedDuration = max(5, min(Self.maxDurationSeconds, durationSeconds))
            resolvedTarget = now.addingTimeInterval(TimeInterval(resolvedDuration))
        }

        let item = ReminderItem(
            title: title,
            durationSeconds: resolvedDuration,
            createdAt: now,
            startedAt: now,
            targetDate: resolvedTarget,
            status: .active,
            accent: accent
        )

        reminders.append(item)
        appendLog(
            kind: .created,
            reminderID: item.id,
            title: item.displayTitle,
            details: "Scheduled for \(item.formattedTargetDate(relativeTo: now)) (\(ReminderItem.formatDuration(resolvedDuration)))"
        )
        persistState()
        onRemindersChanged?()

        if isAnyAppleSyncEnabled, let syncProvider {
            let itemID = item.id
            Task { @MainActor [weak self] in
                let ids = await syncProvider.syncCreated(item)
                self?.setExternalSyncIDs(ids, for: itemID)
            }
        }
        return item
    }

    public func updateReminder(
        id: UUID,
        title: String? = nil,
        durationSeconds: Int? = nil,
        targetDate: Date? = nil,
        accent: AccentPreset? = nil
    ) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders[idx]
        let now = clock.now
        var changeNotes: [String] = []

        if let title {
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned != item.title {
                let oldDisplay = item.displayTitle
                item.title = cleaned
                changeNotes.append("title '\(oldDisplay)' -> '\(item.displayTitle)'")
            }
        }

        if let targetDate {
            let clampedTarget = max(now.addingTimeInterval(10), targetDate)
            let newDuration = max(10, min(Self.maxDurationSeconds, Int(clampedTarget.timeIntervalSince(now).rounded())))
            item.durationSeconds = newDuration
            item.targetDate = clampedTarget
            item.startedAt = now
            if item.status == .paused {
                item.pausedRemainingSeconds = TimeInterval(newDuration)
            } else if item.status == .triggered {
                item.status = .active
            }
            if newDuration > settings.preAlertSeconds {
                item.preAlertSent = false
            }
            changeNotes.append("scheduled for \(item.formattedTargetDate(relativeTo: now))")
        } else if let durationSeconds {
            let clamped = max(10, min(Self.maxDurationSeconds, durationSeconds))
            item.durationSeconds = clamped
            if item.status == .paused {
                item.pausedRemainingSeconds = TimeInterval(clamped)
            } else if item.status == .active || item.status == .triggered {
                item.status = .active
                item.startedAt = now
                item.targetDate = now.addingTimeInterval(TimeInterval(clamped))
                if clamped > settings.preAlertSeconds {
                    item.preAlertSent = false
                }
            }
            changeNotes.append("duration -> \(ReminderItem.formatDuration(clamped))")
        }

        if let accent, accent != item.accent {
            item.accent = accent
        }

        reminders[idx] = item
        if !changeNotes.isEmpty {
            appendLog(
                kind: .edited,
                reminderID: item.id,
                title: item.displayTitle,
                details: changeNotes.joined(separator: "; ")
            )
        }
        persistState()
        onRemindersChanged?()

        if isAnyAppleSyncEnabled, let syncProvider {
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
            let nextRem = max(10, min(TimeInterval(Self.maxDurationSeconds), currentRem + TimeInterval(deltaSeconds)))
            item.targetDate = now.addingTimeInterval(nextRem)
            if Int(nextRem.rounded()) > item.durationSeconds {
                item.durationSeconds = Int(nextRem.rounded())
            }
            if nextRem > TimeInterval(settings.preAlertSeconds) {
                item.preAlertSent = false
            }
        case .paused:
            let currentRem = item.pausedRemainingSeconds ?? TimeInterval(item.durationSeconds)
            let nextRem = max(10, min(TimeInterval(Self.maxDurationSeconds), currentRem + TimeInterval(deltaSeconds)))
            item.pausedRemainingSeconds = nextRem
            if Int(nextRem.rounded()) > item.durationSeconds {
                item.durationSeconds = Int(nextRem.rounded())
            }
        case .triggered, .completed, .dismissed:
            return
        }

        reminders[idx] = item
        let sign = deltaSeconds >= 0 ? "+" : "-"
        appendLog(
            kind: .adjusted,
            reminderID: item.id,
            title: item.displayTitle,
            details: "\(sign)\(ReminderItem.formatDuration(abs(deltaSeconds))) (ends \(item.formattedTargetDate(relativeTo: now)))"
        )
        persistState()

        if isAnyAppleSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func togglePause(id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        var item = reminders[idx]
        let now = clock.now
        let logKind: ActivityEventKind
        let detail: String

        if item.status == .active {
            let rem = max(1, item.targetDate.timeIntervalSince(now))
            item.pausedRemainingSeconds = rem
            item.status = .paused
            logKind = .paused
            detail = "Paused with \(ReminderItem.formatDuration(Int(rem.rounded()))) remaining"
        } else if item.status == .paused {
            let rem = max(1, item.pausedRemainingSeconds ?? TimeInterval(item.durationSeconds))
            item.targetDate = now.addingTimeInterval(rem)
            item.pausedRemainingSeconds = nil
            item.status = .active
            logKind = .resumed
            detail = "Resumed; ends \(item.formattedTargetDate(relativeTo: now))"
        } else {
            return
        }

        reminders[idx] = item
        appendLog(kind: logKind, reminderID: item.id, title: item.displayTitle, details: detail)
        persistState()

        if isAnyAppleSyncEnabled, let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    public func deleteReminder(id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        let removed = reminders.remove(at: idx)
        appendLog(
            kind: .deleted,
            reminderID: removed.id,
            title: removed.displayTitle,
            details: "Removed active reminder"
        )
        persistState()
        onRemindersChanged?()

        if isAnyAppleSyncEnabled,
           (removed.externalReminderID != nil || removed.externalCalendarEventID != nil),
           let syncProvider {
            Task { @MainActor in
                await syncProvider.syncDeleted(
                    reminderID: removed.externalReminderID,
                    calendarEventID: removed.externalCalendarEventID
                )
            }
        }
    }

    public func removeAllActiveRemindersForQuit() {
        let toRemove = reminders.filter { $0.status == .active || $0.status == .paused || $0.status == .triggered }
        guard !toRemove.isEmpty else { return }
        for item in toRemove {
            appendLog(
                kind: .deleted,
                reminderID: item.id,
                title: item.displayTitle,
                details: "Removed before quitting app"
            )
            if isAnyAppleSyncEnabled,
               (item.externalReminderID != nil || item.externalCalendarEventID != nil),
               let syncProvider {
                Task { @MainActor in
                    await syncProvider.syncDeleted(
                        reminderID: item.externalReminderID,
                        calendarEventID: item.externalCalendarEventID
                    )
                }
            }
        }
        reminders.removeAll()
        persistState()
        onRemindersChanged?()
    }

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
                appendLog(
                    kind: .triggered,
                    reminderID: reminders[idx].id,
                    title: reminders[idx].displayTitle,
                    details: "Due time reached"
                )
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
            if !newlyTriggered.isEmpty {
                onRemindersChanged?()
            }
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
        let clamped = max(10, min(Self.maxDurationSeconds, addedSeconds))

        var item = reminders[idx]
        item.status = .active
        item.targetDate = now.addingTimeInterval(TimeInterval(clamped))
        item.durationSeconds = clamped
        item.pausedRemainingSeconds = nil
        item.snoozeCount += 1
        item.totalSnoozedSeconds += clamped
        item.preAlertSent = false

        reminders[idx] = item
        appendLog(
            kind: .snoozed,
            reminderID: item.id,
            title: item.displayTitle,
            details: "Snoozed +\(ReminderItem.formatDuration(clamped)) (#\(item.snoozeCount))"
        )
        persistState()
        onRemindersChanged?()

        if isAnyAppleSyncEnabled, let syncProvider {
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

    private func archiveReminder(
        id: UUID,
        outcome: HistoryOutcome,
        skipExternalReminderCompletion: Bool = false,
        customLogKind: ActivityEventKind? = nil,
        customLogDetail: String? = nil
    ) {
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
        appendLog(
            kind: customLogKind ?? (outcome == .completed ? .completed : .dismissed),
            reminderID: item.id,
            title: item.displayTitle,
            details: customLogDetail ?? (
                outcome == .completed
                    ? "Completed after \(ReminderItem.formatDuration(actualElapsed))"
                    : "Dismissed without completing"
            )
        )
        persistState()
        onRemindersChanged?()

        if isAnyAppleSyncEnabled, let syncProvider {
            if outcome == .completed {
                if !skipExternalReminderCompletion {
                    Task { @MainActor in
                        await syncProvider.syncCompleted(item)
                    }
                }
            } else if item.externalReminderID != nil || item.externalCalendarEventID != nil {
                Task { @MainActor in
                    await syncProvider.syncDeleted(
                        reminderID: item.externalReminderID,
                        calendarEventID: item.externalCalendarEventID
                    )
                }
            }
        }
    }

    public func reconcileAllFromSyncProvider() async {
        guard isAnyAppleSyncEnabled, let syncProvider else { return }
        let snapshotTargets = reminders.filter {
            ($0.status == .active || $0.status == .paused || $0.status == .triggered)
                && ($0.externalReminderID != nil || $0.externalCalendarEventID != nil)
        }
        for item in snapshotTargets {
            guard let snapshot = await syncProvider.fetchExternalSnapshot(for: item) else { continue }
            applyExternalSnapshot(snapshot, for: item.id)
        }
    }

    public func applyExternalSnapshot(_ snapshot: ExternalSyncSnapshot, for reminderID: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminderID }) else { return }
        var item = reminders[idx]
        let now = clock.now

        let reminderDeleted = item.externalReminderID != nil && snapshot.reminderExists == false
        let calendarDeleted = item.externalCalendarEventID != nil && snapshot.calendarEventExists == false

        if reminderDeleted || calendarDeleted {
            reminders.remove(at: idx)
            let source = reminderDeleted ? "Apple Reminders" : "Apple Calendar"
            appendLog(
                kind: .externalSyncDeleted,
                reminderID: item.id,
                title: item.displayTitle,
                details: "Deleted in \(source); removed from SpacedOut"
            )
            persistState()
            onRemindersChanged?()

            if let syncProvider {
                let remainingRemID = reminderDeleted ? nil : item.externalReminderID
                let remainingCalID = calendarDeleted ? nil : item.externalCalendarEventID
                if remainingRemID != nil || remainingCalID != nil {
                    Task { @MainActor in
                        await syncProvider.syncDeleted(reminderID: remainingRemID, calendarEventID: remainingCalID)
                    }
                }
            }
            return
        }

        if snapshot.reminderCompleted {
            archiveReminder(
                id: item.id,
                outcome: .completed,
                skipExternalReminderCompletion: true,
                customLogKind: .externalSyncUpdated,
                customLogDetail: "Marked completed in Apple Reminders"
            )
            return
        }

        // check title or schedule changes from either Apple Reminders or Apple Calendar
        var changedFields: [String] = []
        var changeSource = "Apple Sync"

        let currentTitle = item.displayTitle
        if let rTitle = snapshot.reminderTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rTitle.isEmpty, rTitle != currentTitle {
            item.title = rTitle
            changedFields.append("title -> '\(rTitle)'")
            changeSource = "Apple Reminders"
        } else if let cTitle = snapshot.calendarTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cTitle.isEmpty, cTitle != currentTitle {
            item.title = cTitle
            changedFields.append("title -> '\(cTitle)'")
            changeSource = "Apple Calendar"
        }

        if let rDate = snapshot.reminderTargetDate,
           abs(rDate.timeIntervalSince(item.targetDate)) > 2 {
            applyExternalTargetDate(rDate, onto: &item, now: now)
            changedFields.append("time -> \(item.formattedTargetDate(relativeTo: now))")
            changeSource = "Apple Reminders"
        } else if let cDate = snapshot.calendarTargetDate,
                  abs(cDate.timeIntervalSince(item.targetDate)) > 2 {
            applyExternalTargetDate(cDate, onto: &item, now: now)
            changedFields.append("time -> \(item.formattedTargetDate(relativeTo: now))")
            changeSource = "Apple Calendar"
        }

        guard !changedFields.isEmpty else { return }

        reminders[idx] = item
        appendLog(
            kind: .externalSyncUpdated,
            reminderID: item.id,
            title: item.displayTitle,
            details: "Updated from \(changeSource): \(changedFields.joined(separator: ", "))"
        )
        persistState()
        onRemindersChanged?()

        if let syncProvider {
            Task { @MainActor in
                await syncProvider.syncUpdated(item)
            }
        }
    }

    private func applyExternalTargetDate(_ newDate: Date, onto item: inout ReminderItem, now: Date) {
        item.targetDate = newDate
        if newDate > now {
            let secs = max(10, min(Self.maxDurationSeconds, Int(newDate.timeIntervalSince(now).rounded())))
            item.durationSeconds = secs
            if item.status == .triggered {
                item.status = .active
            }
            if item.status == .paused {
                item.pausedRemainingSeconds = TimeInterval(secs)
            }
            if secs > settings.preAlertSeconds {
                item.preAlertSent = false
            }
        }
    }

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

    public func clearActivityLog() {
        activityLog.removeAll()
        persistState()
    }

    public func recordWatchdogEvent(_ details: String, title: String = "Accountability Watchdog") {
        appendLog(kind: .watchdogEvent, reminderID: nil, title: title, details: details)
        persistState()
    }

    public func touchLastSeen() {
        guard !reminders.isEmpty else { return }
        persistState()
    }

    public func exportActivityLogText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = ["SpacedOut Activity Log (\(activityLog.count) events)", ""]
        for entry in activityLog {
            lines.append("[\(formatter.string(from: entry.timestamp))] [\(entry.kind.label)] \(entry.reminderTitle) — \(entry.details)")
        }
        return lines.joined(separator: "\n") + "\n"
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

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        settings.widgetOpacity = min(1.0, max(0.15, settings.widgetOpacity))
        settings.preAlertSeconds = max(10, min(120, settings.preAlertSeconds))
        settings.defaultDurationMinutes = max(1, min(999, settings.defaultDurationMinutes))
        if settings.quickPresetsMinutes.isEmpty {
            settings.quickPresetsMinutes = [5, 10, 15, 25]
        } else {
            settings.quickPresetsMinutes = settings.quickPresetsMinutes.map { max(1, min(999, $0)) }
        }
        persistState()
        onSettingsChanged?(settings)
        onRemindersChanged?()
    }

    public func setExternalSyncIDs(_ ids: SyncIdentifiers, for id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        if let remID = ids.reminderID {
            reminders[idx].externalReminderID = remID
        }
        if let calID = ids.calendarEventID {
            reminders[idx].externalCalendarEventID = calID
        }
        persistState()
    }

    public func resetAllData() {
        reminders.removeAll()
        history.removeAll()
        activityLog.removeAll()
        settings = AppSettings()
        persistState()
        onSettingsChanged?(settings)
        onRemindersChanged?()
    }

    private func appendLog(kind: ActivityEventKind, reminderID: UUID?, title: String, details: String) {
        let entry = ActivityLogEntry(
            timestamp: clock.now,
            kind: kind,
            reminderID: reminderID,
            reminderTitle: title,
            details: details
        )
        activityLog.insert(entry, at: 0)
        if activityLog.count > Self.maxActivityLogEntries {
            activityLog.removeLast(activityLog.count - Self.maxActivityLogEntries)
        }
    }

    private func loadInitialState() {
        do {
            let loaded = try store.load()
            let now = clock.now
            var recovered = loaded.reminders.filter {
                $0.status == .active || $0.status == .paused || $0.status == .triggered
            }
            self.history = loaded.history.sorted { $0.finishedAt > $1.finishedAt }
            self.activityLog = loaded.activityLog.sorted { $0.timestamp > $1.timestamp }
            var loadedSettings = loaded.settings
            self.lastSeenAt = loaded.lastSeenAt

            // upgrade v1 state so default Apple sync & watchdog turn on seamlessly
            var needsPersist = false
            if loaded.schemaVersion < 2 {
                loadedSettings.appleRemindersSyncEnabled = true
                loadedSettings.appleCalendarSyncEnabled = true
                loadedSettings.accountabilityWatchdogEnabled = true
                needsPersist = true
            }
            self.settings = loadedSettings

            for idx in recovered.indices {
                if recovered[idx].status == .active && recovered[idx].targetDate <= now {
                    recovered[idx].status = .triggered
                    appendLog(
                        kind: .recoveredAfterRestart,
                        reminderID: recovered[idx].id,
                        title: recovered[idx].displayTitle,
                        details: "Expired at \(recovered[idx].formattedTargetDate(relativeTo: now)) while app was closed — re-armed alert on launch"
                    )
                    needsPersist = true
                } else if recovered[idx].status == .triggered {
                    appendLog(
                        kind: .recoveredAfterRestart,
                        reminderID: recovered[idx].id,
                        title: recovered[idx].displayTitle,
                        details: "Unresolved overdue alert restored after restart"
                    )
                    needsPersist = true
                } else if let prevSeen = loaded.lastSeenAt, now.timeIntervalSince(prevSeen) > 15 {
                    let gap = Int(now.timeIntervalSince(prevSeen).rounded())
                    appendLog(
                        kind: .recoveredAfterRestart,
                        reminderID: recovered[idx].id,
                        title: recovered[idx].displayTitle,
                        details: "Restored \(recovered[idx].status.rawValue) timer after restart (offline \(ReminderItem.formatDuration(gap)))"
                    )
                    needsPersist = true
                }
            }

            self.reminders = recovered
            self.lastPersistenceError = nil
            if needsPersist || !recovered.isEmpty {
                persistState()
            }
        } catch {
            self.reminders = []
            self.history = []
            self.activityLog = []
            self.settings = AppSettings()
            self.lastPersistenceError = error.localizedDescription
        }
    }

    private func persistState() {
        let now = clock.now
        lastSeenAt = now
        let snapshot = PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            reminders: reminders,
            history: history,
            activityLog: activityLog,
            settings: settings,
            lastSeenAt: now
        )
        do {
            try store.save(snapshot)
            self.lastPersistenceError = nil
        } catch {
            self.lastPersistenceError = error.localizedDescription
        }
    }
}
