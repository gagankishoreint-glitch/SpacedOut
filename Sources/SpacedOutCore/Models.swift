import Foundation

public enum ReminderStatus: String, Codable, Sendable, CaseIterable {
    case active
    case paused
    case triggered
    case completed
    case dismissed
}

public enum AccentPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case mint
    case sky
    case amber
    case coral
    case slate

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mint: return "Mint"
        case .sky: return "Sky"
        case .amber: return "Amber"
        case .coral: return "Coral"
        case .slate: return "Slate"
        }
    }
}

public struct ReminderItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var durationSeconds: Int
    public let createdAt: Date
    public var startedAt: Date
    public var targetDate: Date
    public var pausedRemainingSeconds: TimeInterval?
    public var status: ReminderStatus
    public var snoozeCount: Int
    public var totalSnoozedSeconds: Int
    public var completedAt: Date?
    public var externalReminderID: String?
    public var externalCalendarEventID: String?
    public var accent: AccentPreset
    public var preAlertSent: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        durationSeconds: Int,
        createdAt: Date,
        startedAt: Date? = nil,
        targetDate: Date,
        pausedRemainingSeconds: TimeInterval? = nil,
        status: ReminderStatus = .active,
        snoozeCount: Int = 0,
        totalSnoozedSeconds: Int = 0,
        completedAt: Date? = nil,
        externalReminderID: String? = nil,
        externalCalendarEventID: String? = nil,
        accent: AccentPreset = .mint,
        preAlertSent: Bool = false
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.durationSeconds = max(1, durationSeconds)
        self.createdAt = createdAt
        self.startedAt = startedAt ?? createdAt
        self.targetDate = targetDate
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.status = status
        self.snoozeCount = snoozeCount
        self.totalSnoozedSeconds = totalSnoozedSeconds
        self.completedAt = completedAt
        self.externalReminderID = externalReminderID
        self.externalCalendarEventID = externalCalendarEventID
        self.accent = accent
        self.preAlertSent = preAlertSent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            durationSeconds: try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 900,
            createdAt: createdAt,
            startedAt: try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? createdAt,
            targetDate: try c.decode(Date.self, forKey: .targetDate),
            pausedRemainingSeconds: try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemainingSeconds),
            status: try c.decodeIfPresent(ReminderStatus.self, forKey: .status) ?? .active,
            snoozeCount: try c.decodeIfPresent(Int.self, forKey: .snoozeCount) ?? 0,
            totalSnoozedSeconds: try c.decodeIfPresent(Int.self, forKey: .totalSnoozedSeconds) ?? 0,
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            externalReminderID: try c.decodeIfPresent(String.self, forKey: .externalReminderID),
            externalCalendarEventID: try c.decodeIfPresent(String.self, forKey: .externalCalendarEventID),
            accent: try c.decodeIfPresent(AccentPreset.self, forKey: .accent) ?? .mint,
            preAlertSent: try c.decodeIfPresent(Bool.self, forKey: .preAlertSent) ?? false
        )
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Quick Reminder" : trimmed
    }

    public var isSyncedExternally: Bool {
        externalReminderID != nil || externalCalendarEventID != nil
    }

    public func formattedTargetDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.locale = Locale.current
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        let timePart = timeFmt.string(from: targetDate)

        if calendar.isDate(targetDate, inSameDayAs: now) {
            return timePart
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(targetDate, inSameDayAs: tomorrow) {
            return "Tomorrow, \(timePart)"
        }
        let dateFmt = DateFormatter()
        dateFmt.calendar = calendar
        dateFmt.locale = Locale.current
        dateFmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(dateFmt.string(from: targetDate)), \(timePart)"
    }

    public func remainingSeconds(at now: Date) -> TimeInterval {
        switch status {
        case .paused:
            return max(0, pausedRemainingSeconds ?? 0)
        case .active:
            return max(0, targetDate.timeIntervalSince(now))
        case .triggered:
            return targetDate.timeIntervalSince(now)
        case .completed, .dismissed:
            return 0
        }
    }

    public func progressFraction(at now: Date) -> Double {
        let total = max(1.0, Double(durationSeconds))
        switch status {
        case .paused:
            let rem = max(0, pausedRemainingSeconds ?? total)
            return min(1.0, max(0.0, 1.0 - rem / total))
        case .active:
            let rem = max(0, targetDate.timeIntervalSince(now))
            return min(1.0, max(0.0, 1.0 - rem / total))
        case .triggered, .completed, .dismissed:
            return 1.0
        }
    }

    public func formattedRemaining(at now: Date) -> String {
        let raw = remainingSeconds(at: now)
        if status == .triggered && raw < 0 {
            return "+" + Self.formatDuration(Int(abs(raw).rounded(.down)))
        }
        let roundedUp = Int(ceil(max(0, raw)))
        return Self.formatDuration(roundedUp)
    }

    public static func formatDuration(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        if clamped >= 86400 {
            let days = clamped / 86400
            let hours = (clamped % 86400) / 3600
            let mins = (clamped % 3600) / 60
            return hours > 0 ? "\(days)d \(hours)h" : (mins > 0 ? "\(days)d \(mins)m" : "\(days)d")
        }
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public enum HistoryOutcome: String, Codable, Sendable, CaseIterable {
    case completed
    case dismissed
}

public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var plannedDurationSeconds: Int
    public var actualElapsedSeconds: Int
    public let createdAt: Date
    public let finishedAt: Date
    public let outcome: HistoryOutcome
    public let snoozeCount: Int
    public let accent: AccentPreset

    public init(
        id: UUID = UUID(),
        title: String,
        plannedDurationSeconds: Int,
        actualElapsedSeconds: Int,
        createdAt: Date,
        finishedAt: Date,
        outcome: HistoryOutcome,
        snoozeCount: Int,
        accent: AccentPreset = .mint
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.plannedDurationSeconds = max(1, plannedDurationSeconds)
        self.actualElapsedSeconds = max(0, actualElapsedSeconds)
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.snoozeCount = max(0, snoozeCount)
        self.accent = accent
    }

    public var displayTitle: String {
        title.isEmpty ? "Quick Reminder" : title
    }
}

public struct DailyFocusStats: Equatable, Sendable {
    public let completedCount: Int
    public let dismissedCount: Int
    public let totalFocusMinutes: Int
    public let onTimeCount: Int

    public init(completedCount: Int, dismissedCount: Int, totalFocusMinutes: Int, onTimeCount: Int) {
        self.completedCount = completedCount
        self.dismissedCount = dismissedCount
        self.totalFocusMinutes = totalFocusMinutes
        self.onTimeCount = onTimeCount
    }

    public var onTimePercentage: Int {
        guard completedCount > 0 else { return 100 }
        return Int((Double(onTimeCount) / Double(completedCount) * 100.0).rounded())
    }
}

public enum DisplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case widgetAndMenuBar
    case menuBarOnly
    case widgetOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .widgetAndMenuBar: return "Widget & Menu Bar"
        case .menuBarOnly: return "Menu Bar Only"
        case .widgetOnly: return "Floating Widget Only"
        }
    }

    public var subtitle: String {
        switch self {
        case .widgetAndMenuBar:
            return "Keep the frosted widget on screen plus a live countdown in the menu bar."
        case .menuBarOnly:
            return "Live cleanly in the menu bar; open the widget anytime via icon or shortcut."
        case .widgetOnly:
            return "Display only the floating desktop widget without a menu bar item."
        }
    }
}

public enum ThemeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Frosted Light"
        case .dark: return "Midnight Glass"
        }
    }
}

public enum WidgetScale: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact
    case regular
    case comfortable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .comfortable: return "Comfortable"
        }
    }

    public var width: Double {
        switch self {
        case .compact: return 320
        case .regular: return 360
        case .comfortable: return 408
        }
    }
}

public enum NotificationStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case fullScreen
    case fullScreenWithPreAlert
    case bannerOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullScreen: return "Full-Screen Takeover"
        case .fullScreenWithPreAlert: return "Full-Screen + 30s Pre-Alert"
        case .bannerOnly: return "Standard Notification Banner"
        }
    }

    public var description: String {
        switch self {
        case .fullScreen:
            return "Covers all displays when time expires so hyperfocus never wins."
        case .fullScreenWithPreAlert:
            return "Shows a subtle 30-second countdown nudge before taking over the screen."
        case .bannerOnly:
            return "Uses native macOS notifications without a full-screen overlay."
        }
    }
}

public enum SoundPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case glassChime
    case warmMarimba
    case softBell
    case crystalPulse
    case silent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glassChime: return "Glass Chime"
        case .warmMarimba: return "Warm Marimba"
        case .softBell: return "Soft Bell"
        case .crystalPulse: return "Crystal Pulse"
        case .silent: return "Silent"
        }
    }
}

public struct HotkeyModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option  = HotkeyModifiers(rawValue: 1 << 1)
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift   = HotkeyModifiers(rawValue: 1 << 3)
}

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: HotkeyModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    // option+space (Carbon kVK_Space = 49)
    public static let defaultToggleWidget = HotkeyBinding(
        keyCode: 49,
        modifiers: [.option],
        keyLabel: "Space"
    )

    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts.joined(separator: " ")
    }
}

public struct SavedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum ActivityEventKind: String, Codable, Sendable, CaseIterable {
    case created
    case edited
    case adjusted
    case paused
    case resumed
    case snoozed
    case triggered
    case completed
    case dismissed
    case deleted
    case recoveredAfterRestart
    case externalSyncUpdated
    case externalSyncDeleted
    case watchdogEvent

    public var label: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .adjusted: return "Adjusted"
        case .paused: return "Paused"
        case .resumed: return "Resumed"
        case .snoozed: return "Snoozed"
        case .triggered: return "Due"
        case .completed: return "Completed"
        case .dismissed: return "Dismissed"
        case .deleted: return "Removed"
        case .recoveredAfterRestart: return "Restart Recovery"
        case .externalSyncUpdated: return "Apple Sync"
        case .externalSyncDeleted: return "Apple Sync"
        case .watchdogEvent: return "Watchdog"
        }
    }

    public var category: ActivityLogCategory {
        switch self {
        case .created, .paused, .resumed, .triggered, .completed, .dismissed, .deleted:
            return .timers
        case .edited, .adjusted, .snoozed:
            return .edits
        case .externalSyncUpdated, .externalSyncDeleted:
            return .sync
        case .recoveredAfterRestart, .watchdogEvent:
            return .system
        }
    }
}

public enum ActivityLogCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case all = "All"
    case timers = "Timers"
    case edits = "Edits"
    case sync = "Sync"
    case system = "Restarts"

    public var id: String { rawValue }
}

public struct ActivityLogEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: ActivityEventKind
    public let reminderID: UUID?
    public let reminderTitle: String
    public let details: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: ActivityEventKind,
        reminderID: UUID? = nil,
        reminderTitle: String,
        details: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.reminderID = reminderID
        let trimmed = reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reminderTitle = trimmed.isEmpty ? "Quick Reminder" : trimmed
        self.details = details
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var displayMode: DisplayMode
    public var themeMode: ThemeMode
    public var widgetScale: WidgetScale
    public var widgetOpacity: Double
    public var alwaysOnTop: Bool
    public var showDockIcon: Bool
    public var notificationStyle: NotificationStyle
    public var preAlertSeconds: Int
    public var presentationSafeMode: Bool
    public var soundEnabled: Bool
    public var soundPreset: SoundPreset
    public var hapticsEnabled: Bool
    public var quickPresetsMinutes: [Int]
    public var defaultDurationMinutes: Int
    public var globalShortcut: HotkeyBinding
    public var appleRemindersSyncEnabled: Bool
    public var appleRemindersListName: String
    public var appleCalendarSyncEnabled: Bool
    public var appleCalendarName: String
    public var accountabilityWatchdogEnabled: Bool
    public var widgetOrigin: SavedPoint?
    public var launchAtLogin: Bool

    public init(
        displayMode: DisplayMode = .widgetAndMenuBar,
        themeMode: ThemeMode = .system,
        widgetScale: WidgetScale = .regular,
        widgetOpacity: Double = 0.94,
        alwaysOnTop: Bool = true,
        showDockIcon: Bool = false,
        notificationStyle: NotificationStyle = .fullScreenWithPreAlert,
        preAlertSeconds: Int = 30,
        presentationSafeMode: Bool = false,
        soundEnabled: Bool = true,
        soundPreset: SoundPreset = .glassChime,
        hapticsEnabled: Bool = true,
        quickPresetsMinutes: [Int] = [5, 10, 15, 25],
        defaultDurationMinutes: Int = 15,
        globalShortcut: HotkeyBinding = .defaultToggleWidget,
        appleRemindersSyncEnabled: Bool = true,
        appleRemindersListName: String = "SpacedOut",
        appleCalendarSyncEnabled: Bool = true,
        appleCalendarName: String = "SpacedOut",
        accountabilityWatchdogEnabled: Bool = true,
        widgetOrigin: SavedPoint? = nil,
        launchAtLogin: Bool = false
    ) {
        self.displayMode = displayMode
        self.themeMode = themeMode
        self.widgetScale = widgetScale
        self.widgetOpacity = min(1.0, max(0.72, widgetOpacity))
        self.alwaysOnTop = alwaysOnTop
        self.showDockIcon = showDockIcon
        self.notificationStyle = notificationStyle
        self.preAlertSeconds = max(10, min(120, preAlertSeconds))
        self.presentationSafeMode = presentationSafeMode
        self.soundEnabled = soundEnabled
        self.soundPreset = soundPreset
        self.hapticsEnabled = hapticsEnabled
        self.quickPresetsMinutes = quickPresetsMinutes.isEmpty ? [5, 10, 15, 25] : quickPresetsMinutes.map { max(1, min(999, $0)) }
        self.defaultDurationMinutes = max(1, min(999, defaultDurationMinutes))
        self.globalShortcut = globalShortcut
        self.appleRemindersSyncEnabled = appleRemindersSyncEnabled
        self.appleRemindersListName = appleRemindersListName.isEmpty ? "SpacedOut" : appleRemindersListName
        self.appleCalendarSyncEnabled = appleCalendarSyncEnabled
        self.appleCalendarName = appleCalendarName.isEmpty ? "SpacedOut" : appleCalendarName
        self.accountabilityWatchdogEnabled = accountabilityWatchdogEnabled
        self.widgetOrigin = widgetOrigin
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.init(
            displayMode: try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode,
            themeMode: try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? defaults.themeMode,
            widgetScale: try c.decodeIfPresent(WidgetScale.self, forKey: .widgetScale) ?? defaults.widgetScale,
            widgetOpacity: try c.decodeIfPresent(Double.self, forKey: .widgetOpacity) ?? defaults.widgetOpacity,
            alwaysOnTop: try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? defaults.alwaysOnTop,
            showDockIcon: try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? defaults.showDockIcon,
            notificationStyle: try c.decodeIfPresent(NotificationStyle.self, forKey: .notificationStyle) ?? defaults.notificationStyle,
            preAlertSeconds: try c.decodeIfPresent(Int.self, forKey: .preAlertSeconds) ?? defaults.preAlertSeconds,
            presentationSafeMode: try c.decodeIfPresent(Bool.self, forKey: .presentationSafeMode) ?? defaults.presentationSafeMode,
            soundEnabled: try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled,
            soundPreset: try c.decodeIfPresent(SoundPreset.self, forKey: .soundPreset) ?? defaults.soundPreset,
            hapticsEnabled: try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? defaults.hapticsEnabled,
            quickPresetsMinutes: try c.decodeIfPresent([Int].self, forKey: .quickPresetsMinutes) ?? defaults.quickPresetsMinutes,
            defaultDurationMinutes: try c.decodeIfPresent(Int.self, forKey: .defaultDurationMinutes) ?? defaults.defaultDurationMinutes,
            globalShortcut: try c.decodeIfPresent(HotkeyBinding.self, forKey: .globalShortcut) ?? defaults.globalShortcut,
            appleRemindersSyncEnabled: try c.decodeIfPresent(Bool.self, forKey: .appleRemindersSyncEnabled) ?? defaults.appleRemindersSyncEnabled,
            appleRemindersListName: try c.decodeIfPresent(String.self, forKey: .appleRemindersListName) ?? defaults.appleRemindersListName,
            appleCalendarSyncEnabled: try c.decodeIfPresent(Bool.self, forKey: .appleCalendarSyncEnabled) ?? defaults.appleCalendarSyncEnabled,
            appleCalendarName: try c.decodeIfPresent(String.self, forKey: .appleCalendarName) ?? defaults.appleCalendarName,
            accountabilityWatchdogEnabled: try c.decodeIfPresent(Bool.self, forKey: .accountabilityWatchdogEnabled) ?? defaults.accountabilityWatchdogEnabled,
            widgetOrigin: try c.decodeIfPresent(SavedPoint.self, forKey: .widgetOrigin),
            launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        )
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var reminders: [ReminderItem]
    public var history: [HistoryEntry]
    public var activityLog: [ActivityLogEntry]
    public var settings: AppSettings
    public var lastSeenAt: Date?

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        reminders: [ReminderItem] = [],
        history: [HistoryEntry] = [],
        activityLog: [ActivityLogEntry] = [],
        settings: AppSettings = AppSettings(),
        lastSeenAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.reminders = reminders
        self.history = history
        self.activityLog = activityLog
        self.settings = settings
        self.lastSeenAt = lastSeenAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.reminders = try c.decodeIfPresent([ReminderItem].self, forKey: .reminders) ?? []
        self.history = try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        self.activityLog = try c.decodeIfPresent([ActivityLogEntry].self, forKey: .activityLog) ?? []
        self.settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        self.lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }
}
