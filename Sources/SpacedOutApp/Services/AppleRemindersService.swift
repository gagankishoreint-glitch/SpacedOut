import AppKit
import EventKit
import Foundation
import Observation
import SpacedOutCore

enum RemindersAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case writeOnly
    case unavailableUnbundled

    var label: String {
        switch self {
        case .notDetermined: return "Not Requested"
        case .authorized: return "Connected"
        case .denied: return "Denied in System Settings"
        case .restricted: return "Restricted"
        case .writeOnly: return "Write-Only (Full Access Needed)"
        case .unavailableUnbundled: return "Requires .app Bundle"
        }
    }
}

@MainActor
@Observable
final class AppleRemindersService: AppleSyncProviding {
    private let eventStore = EKEventStore()

    var authState: RemindersAuthState = .notDetermined
    var calendarAuthState: RemindersAuthState = .notDetermined
    var availableLists: [String] = []
    var availableCalendars: [String] = []
    var lastSyncError: String?

    var onExternalStoreChanged: (@MainActor () -> Void)?

    private var remindersSyncEnabled: Bool = true
    private var calendarSyncEnabled: Bool = true
    private var targetListName: String = "SpacedOut"
    private var targetCalendarName: String = "SpacedOut"

    private var storeObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var suppressExternalNotificationUntil: Date = .distantPast

    private var canUseRemindersSafely: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    private var canUseCalendarSafely: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    init() {
        refreshStatus()
        installStoreObserver()
    }

    func configure(
        remindersEnabled: Bool,
        remindersListName: String,
        calendarEnabled: Bool,
        calendarName: String
    ) {
        self.remindersSyncEnabled = remindersEnabled
        self.calendarSyncEnabled = calendarEnabled
        let trimmedList = remindersListName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetListName = trimmedList.isEmpty ? "SpacedOut" : trimmedList
        let trimmedCal = calendarName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetCalendarName = trimmedCal.isEmpty ? "SpacedOut" : trimmedCal
    }

    func refreshStatus() {
        if canUseRemindersSafely {
            authState = mapStatus(EKEventStore.authorizationStatus(for: .reminder))
            if authState == .authorized { reloadLists() } else { availableLists = [] }
        } else {
            authState = .unavailableUnbundled
            availableLists = []
        }

        if canUseCalendarSafely {
            calendarAuthState = mapStatus(EKEventStore.authorizationStatus(for: .event))
            if calendarAuthState == .authorized { reloadCalendars() } else { availableCalendars = [] }
        } else {
            calendarAuthState = .unavailableUnbundled
            availableCalendars = []
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        guard canUseRemindersSafely else {
            authState = .unavailableUnbundled
            return false
        }
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            refreshStatus()
            lastSyncError = nil
            return granted
        } catch {
            lastSyncError = error.localizedDescription
            refreshStatus()
            return false
        }
    }

    @discardableResult
    func requestCalendarAccess() async -> Bool {
        guard canUseCalendarSafely else {
            calendarAuthState = .unavailableUnbundled
            return false
        }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            refreshStatus()
            lastSyncError = nil
            return granted
        } catch {
            lastSyncError = error.localizedDescription
            refreshStatus()
            return false
        }
    }

    func requestDefaultAccessIfNeeded(reminders: Bool, calendar: Bool) async {
        refreshStatus()
        if reminders && authState == .notDetermined {
            _ = await requestAccess()
        }
        if calendar && calendarAuthState == .notDetermined {
            _ = await requestCalendarAccess()
        }
    }

    func openSystemRemindersPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSystemCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reloadLists() {
        guard authState == .authorized else {
            availableLists = []
            return
        }
        availableLists = eventStore.calendars(for: .reminder)
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func reloadCalendars() {
        guard calendarAuthState == .authorized else {
            availableCalendars = []
            return
        }
        availableCalendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func syncCreated(_ reminder: ReminderItem) async -> SyncIdentifiers {
        var ids = SyncIdentifiers()

        if remindersSyncEnabled, await ensureRemindersAuthorized() {
            if let calendar = resolveTargetReminderList() {
                let ekReminder = EKReminder(eventStore: eventStore)
                ekReminder.title = reminder.displayTitle
                ekReminder.notes = "Created with SpacedOut [\(reminder.id.uuidString)]"
                ekReminder.calendar = calendar
                ekReminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: reminder.targetDate
                )
                ekReminder.addAlarm(EKAlarm(absoluteDate: reminder.targetDate))

                markLocalWrite()
                do {
                    try eventStore.save(ekReminder, commit: true)
                    ids.reminderID = ekReminder.calendarItemIdentifier
                    lastSyncError = nil
                } catch {
                    lastSyncError = error.localizedDescription
                }
            }
        }

        if calendarSyncEnabled, await ensureCalendarAuthorized() {
            if let cal = resolveTargetEventCalendar() {
                let ekEvent = EKEvent(eventStore: eventStore)
                ekEvent.title = reminder.displayTitle
                ekEvent.notes = "Created with SpacedOut [\(reminder.id.uuidString)]"
                ekEvent.calendar = cal
                ekEvent.startDate = reminder.targetDate
                ekEvent.endDate = reminder.targetDate.addingTimeInterval(15 * 60)
                ekEvent.addAlarm(EKAlarm(relativeOffset: 0))

                markLocalWrite()
                do {
                    try eventStore.save(ekEvent, span: .thisEvent, commit: true)
                    ids.calendarEventID = ekEvent.calendarItemIdentifier
                    lastSyncError = nil
                } catch {
                    lastSyncError = error.localizedDescription
                }
            }
        }

        return ids
    }

    func syncUpdated(_ reminder: ReminderItem) async {
        if remindersSyncEnabled, let remID = reminder.externalReminderID,
           await ensureRemindersAuthorized(),
           let ekReminder = eventStore.calendarItem(withIdentifier: remID) as? EKReminder {
            ekReminder.title = reminder.displayTitle
            ekReminder.alarms?.forEach { ekReminder.removeAlarm($0) }
            if reminder.status == .paused {
                ekReminder.dueDateComponents = nil
            } else {
                ekReminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: reminder.targetDate
                )
                ekReminder.addAlarm(EKAlarm(absoluteDate: reminder.targetDate))
            }
            markLocalWrite()
            do {
                try eventStore.save(ekReminder, commit: true)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }

        if calendarSyncEnabled, let calID = reminder.externalCalendarEventID,
           await ensureCalendarAuthorized(),
           let ekEvent = lookupEvent(identifier: calID) {
            ekEvent.title = reminder.status == .paused
                ? "[Paused] \(reminder.displayTitle)"
                : reminder.displayTitle
            ekEvent.startDate = reminder.targetDate
            ekEvent.endDate = reminder.targetDate.addingTimeInterval(15 * 60)
            ekEvent.alarms?.forEach { ekEvent.removeAlarm($0) }
            if reminder.status != .paused {
                ekEvent.addAlarm(EKAlarm(relativeOffset: 0))
            }
            markLocalWrite()
            do {
                try eventStore.save(ekEvent, span: .thisEvent, commit: true)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }

    func syncCompleted(_ reminder: ReminderItem) async {
        if remindersSyncEnabled, let remID = reminder.externalReminderID,
           await ensureRemindersAuthorized(),
           let ekReminder = eventStore.calendarItem(withIdentifier: remID) as? EKReminder {
            ekReminder.isCompleted = true
            ekReminder.completionDate = Date()
            markLocalWrite()
            do {
                try eventStore.save(ekReminder, commit: true)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }

    func syncDeleted(reminderID: String?, calendarEventID: String?) async {
        if let remID = reminderID, await ensureRemindersAuthorized(),
           let ekReminder = eventStore.calendarItem(withIdentifier: remID) as? EKReminder {
            markLocalWrite()
            do {
                try eventStore.remove(ekReminder, commit: true)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }

        if let calID = calendarEventID, await ensureCalendarAuthorized(),
           let ekEvent = lookupEvent(identifier: calID) {
            markLocalWrite()
            do {
                try eventStore.remove(ekEvent, span: .thisEvent, commit: true)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }

    func fetchExternalSnapshot(for reminder: ReminderItem) async -> ExternalSyncSnapshot? {
        refreshStatus()
        var snapshot = ExternalSyncSnapshot()
        var checkedAnything = false

        if remindersSyncEnabled, authState == .authorized, let remID = reminder.externalReminderID {
            checkedAnything = true
            if let ekReminder = eventStore.calendarItem(withIdentifier: remID) as? EKReminder {
                snapshot.reminderExists = true
                snapshot.reminderCompleted = ekReminder.isCompleted
                snapshot.reminderTitle = ekReminder.title
                if let dueComps = ekReminder.dueDateComponents {
                    snapshot.reminderTargetDate = Calendar.current.date(from: dueComps)
                }
            } else {
                snapshot.reminderExists = false
            }
        }

        if calendarSyncEnabled, calendarAuthState == .authorized, let calID = reminder.externalCalendarEventID {
            checkedAnything = true
            if let ekEvent = lookupEvent(identifier: calID) {
                snapshot.calendarEventExists = true
                let rawTitle = ekEvent.title ?? ""
                snapshot.calendarTitle = rawTitle.hasPrefix("[Paused] ")
                    ? String(rawTitle.dropFirst("[Paused] ".count))
                    : rawTitle
                snapshot.calendarTargetDate = ekEvent.startDate
            } else {
                snapshot.calendarEventExists = false
            }
        }

        return checkedAnything ? snapshot : nil
    }

    private func lookupEvent(identifier: String) -> EKEvent? {
        if let byItemID = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent {
            return byItemID
        }
        return eventStore.event(withIdentifier: identifier)
    }

    private func mapStatus(_ status: EKAuthorizationStatus) -> RemindersAuthState {
        switch status {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .authorized
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    private func ensureRemindersAuthorized() async -> Bool {
        refreshStatus()
        if authState == .authorized { return true }
        if authState == .notDetermined { return await requestAccess() }
        return false
    }

    private func ensureCalendarAuthorized() async -> Bool {
        refreshStatus()
        if calendarAuthState == .authorized { return true }
        if calendarAuthState == .notDetermined { return await requestCalendarAccess() }
        return false
    }

    private func resolveTargetReminderList() -> EKCalendar? {
        let lists = eventStore.calendars(for: .reminder)
        if let existing = lists.first(where: { $0.title.caseInsensitiveCompare(targetListName) == .orderedSame }) {
            return existing
        }
        if let source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
            let created = EKCalendar(for: .reminder, eventStore: eventStore)
            created.title = targetListName
            created.source = source
            do {
                try eventStore.saveCalendar(created, commit: true)
                reloadLists()
                return created
            } catch {
                // some accounts disallow creating custom reminder lists
            }
        }
        return eventStore.defaultCalendarForNewReminders() ?? lists.first(where: \.allowsContentModifications)
    }

    private func resolveTargetEventCalendar() -> EKCalendar? {
        let cals = eventStore.calendars(for: .event).filter(\.allowsContentModifications)
        if let existing = cals.first(where: { $0.title.caseInsensitiveCompare(targetCalendarName) == .orderedSame }) {
            return existing
        }
        if let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
            let created = EKCalendar(for: .event, eventStore: eventStore)
            created.title = targetCalendarName
            created.source = source
            do {
                try eventStore.saveCalendar(created, commit: true)
                reloadCalendars()
                return created
            } catch {
                // fall back to default calendar when source blocks custom calendars
            }
        }
        return eventStore.defaultCalendarForNewEvents ?? cals.first
    }

    private func markLocalWrite() {
        suppressExternalNotificationUntil = Date().addingTimeInterval(1.5)
    }

    private func installStoreObserver() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleExternalReconciliation()
            }
        }
    }

    private func scheduleExternalReconciliation() {
        guard Date() >= suppressExternalNotificationUntil else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            guard Date() >= self.suppressExternalNotificationUntil else { return }
            self.onExternalStoreChanged?()
        }
    }
}
