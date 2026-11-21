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
final class AppleRemindersService: RemindersSyncProviding {
    private let eventStore = EKEventStore()

    var authState: RemindersAuthState = .notDetermined
    var availableLists: [String] = []
    var lastSyncError: String?

    private var targetListName: String = "SpacedOut"

    private var canUseEventKitSafely: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    init() {
        refreshStatus()
    }

    func configureTargetList(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        targetListName = trimmed.isEmpty ? "SpacedOut" : trimmed
    }

    func refreshStatus() {
        guard canUseEventKitSafely else {
            authState = .unavailableUnbundled
            availableLists = []
            return
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .notDetermined:
            authState = .notDetermined
        case .fullAccess:
            authState = .authorized
            reloadLists()
        case .writeOnly:
            authState = .writeOnly
        case .denied:
            authState = .denied
        case .restricted:
            authState = .restricted
        @unknown default:
            authState = .notDetermined
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        guard canUseEventKitSafely else {
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

    func openSystemRemindersPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
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

    func syncCreated(_ reminder: ReminderItem) async -> String? {
        guard await ensureAuthorized() else { return nil }
        guard let calendar = resolveTargetCalendar() else { return nil }

        let ekReminder = EKReminder(eventStore: eventStore)
        ekReminder.title = reminder.displayTitle
        ekReminder.notes = "Created with SpacedOut"
        ekReminder.calendar = calendar
        ekReminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.targetDate
        )
        ekReminder.addAlarm(EKAlarm(absoluteDate: reminder.targetDate))

        do {
            try eventStore.save(ekReminder, commit: true)
            lastSyncError = nil
            return ekReminder.calendarItemIdentifier
        } catch {
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func syncUpdated(_ reminder: ReminderItem) async {
        guard await ensureAuthorized() else { return }
        guard let extID = reminder.externalReminderID,
              let ekReminder = eventStore.calendarItem(withIdentifier: extID) as? EKReminder else {
            return
        }

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

        do {
            try eventStore.save(ekReminder, commit: true)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func syncCompleted(_ reminder: ReminderItem) async {
        guard await ensureAuthorized() else { return }
        guard let extID = reminder.externalReminderID,
              let ekReminder = eventStore.calendarItem(withIdentifier: extID) as? EKReminder else {
            return
        }

        ekReminder.isCompleted = true
        ekReminder.completionDate = Date()

        do {
            try eventStore.save(ekReminder, commit: true)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func syncDeleted(externalID: String) async {
        guard await ensureAuthorized() else { return }
        guard let ekReminder = eventStore.calendarItem(withIdentifier: externalID) as? EKReminder else {
            return
        }

        do {
            try eventStore.remove(ekReminder, commit: true)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func ensureAuthorized() async -> Bool {
        refreshStatus()
        if authState == .authorized { return true }
        if authState == .notDetermined {
            return await requestAccess()
        }
        return false
    }

    private func resolveTargetCalendar() -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title.caseInsensitiveCompare(targetListName) == .orderedSame }) {
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
                // some accounts reject custom reminder lists, fall back below
            }
        }

        return eventStore.defaultCalendarForNewReminders()
    }
}
