import AppKit
import Foundation
import Observation
import SpacedOutCore
import UniformTypeIdentifiers

enum AlertResolutionAction: Sendable {
    case complete
    case dismiss
    case snooze(seconds: Int)
}

@MainActor
@Observable
final class AppCoordinator {
    let engine: TimerEngine
    let soundHaptics: SoundHapticsService
    let remindersSync: AppleRemindersService
    let notifications: NotificationService
    let hotkeyManager: GlobalHotkeyManager
    let watchdog: WatchdogService

    var isWidgetVisible: Bool = false
    var isMenuBarPopoverVisible: Bool = false
    var isDialExpanded: Bool = false
    var selectedDialMinutes: Int
    var focusInputTrigger: UUID = UUID()
    var lastHotkeyError: String?
    var testPreviewReminder: ReminderItem?

    private var floatingWidgetController: FloatingWidgetController?
    private var fullScreenAlertController: FullScreenAlertController?
    private var statusBarController: StatusBarController?
    private var utilityWindowManager: UtilityWindowManager?

    private var evaluationTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var tickCounter: Int = 0
    private var didStart = false

    init() {
        let engine = TimerEngine()
        let remindersSync = AppleRemindersService()
        remindersSync.configure(
            remindersEnabled: engine.settings.appleRemindersSyncEnabled,
            remindersListName: engine.settings.appleRemindersListName,
            calendarEnabled: engine.settings.appleCalendarSyncEnabled,
            calendarName: engine.settings.appleCalendarName
        )
        engine.attachSyncProvider(remindersSync)

        self.engine = engine
        self.soundHaptics = SoundHapticsService()
        self.remindersSync = remindersSync
        self.notifications = NotificationService()
        self.hotkeyManager = GlobalHotkeyManager()
        self.watchdog = WatchdogService()
        self.selectedDialMinutes = engine.settings.defaultDurationMinutes

        wireEngineCallbacks()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        watchdog.markRunningInstance()
        if watchdog.consumeWatchdogRelaunchFlag() {
            engine.recordWatchdogEvent("Auto-relaunched SpacedOut while active reminder(s) were running")
        }
        watchdog.syncState(armed: engine.shouldArmWatchdog)

        applyActivationPolicy(showDockIcon: engine.settings.showDockIcon)

        notifications.configure()
        notifications.onAction = { [weak self] reminderID, actionID in
            guard let self else { return }
            if NotificationService.isCompleteAction(actionID) {
                self.resolveAlert(id: reminderID, action: .complete)
            } else if NotificationService.isSnoozeAction(actionID) {
                self.resolveAlert(id: reminderID, action: .snooze(seconds: 300))
            } else {
                self.showFloatingWidget(focusInput: false)
            }
        }

        remindersSync.onExternalStoreChanged = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reconcileAppleSyncNow()
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.notifications.requestPermissionIfNeeded()
            await self.remindersSync.requestDefaultAccessIfNeeded(
                reminders: self.engine.settings.appleRemindersSyncEnabled,
                calendar: self.engine.settings.appleCalendarSyncEnabled
            )
            await self.reconcileAppleSyncNow()
        }

        floatingWidgetController = FloatingWidgetController(coordinator: self)
        fullScreenAlertController = FullScreenAlertController(coordinator: self)
        statusBarController = StatusBarController(coordinator: self)
        utilityWindowManager = UtilityWindowManager(coordinator: self)

        registerCurrentHotkey()
        applyDisplayMode(engine.settings.displayMode, initialLaunch: true)

        // re-evaluate immediately after sleep so overdue alerts don't wait
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTimersNow()
                await self?.reconcileAppleSyncNow()
            }
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTick()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer

        let hadPreexistingOverdue = !engine.triggeredQueue.isEmpty
        evaluateTimersNow()
        if hadPreexistingOverdue {
            handleTriggeredBatch(engine.triggeredQueue)
        } else {
            refreshAlertPresentation()
        }
    }

    func shutdown() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        hotkeyManager.shutdown()
        engine.touchLastSeen()
        watchdog.clearRunningInstanceIfOwned()
    }

    func showFloatingWidget(focusInput: Bool = false) {
        floatingWidgetController?.show(focusInput: focusInput)
        isWidgetVisible = true
        if focusInput {
            focusInputTrigger = UUID()
        }
    }

    func hideFloatingWidget() {
        floatingWidgetController?.hide()
        isWidgetVisible = false
    }

    func ensureActivePanelKey() {
        if isMenuBarPopoverVisible {
            statusBarController?.makePopoverKeyIfVisible()
        } else {
            floatingWidgetController?.makeKeyIfVisible()
        }
    }

    func toggleFloatingWidget(focusInput: Bool = true) {
        if isWidgetVisible {
            hideFloatingWidget()
        } else {
            showFloatingWidget(focusInput: focusInput)
        }
    }

    func togglePrimaryViaHotkey() {
        switch engine.settings.displayMode {
        case .menuBarOnly:
            statusBarController?.togglePopover()
        case .widgetAndMenuBar, .widgetOnly:
            toggleFloatingWidget(focusInput: true)
        }
    }

    func openHistoryWindow() {
        utilityWindowManager?.showHistory()
    }

    func openSettingsWindow() {
        utilityWindowManager?.showSettings()
    }

    func openScreenTimeSettings(subpath: String? = nil) {
        let base = "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"
        let raw = subpath.map { "\(base)?path=\($0)" } ?? base
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    func applyDisplayMode(_ mode: DisplayMode, initialLaunch: Bool = false) {
        switch mode {
        case .widgetAndMenuBar:
            statusBarController?.setVisible(true)
            statusBarController?.closePopover()
            if initialLaunch || !isWidgetVisible {
                showFloatingWidget(focusInput: false)
            }
        case .menuBarOnly:
            statusBarController?.setVisible(true)
            hideFloatingWidget()
        case .widgetOnly:
            statusBarController?.closePopover()
            statusBarController?.setVisible(false)
            showFloatingWidget(focusInput: false)
        }
    }

    func applyActivationPolicy(showDockIcon: Bool) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    func resetWidgetPosition() {
        engine.updateSettings { $0.widgetOrigin = nil }
        floatingWidgetController?.resetToDefaultPosition()
    }

    @discardableResult
    func createQuickReminder(from rawInput: String) -> ReminderItem {
        let item = engine.createFromQuickInput(
            rawInput,
            fallbackDurationSeconds: selectedDialMinutes * 60
        )
        soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
        return item
    }

    @discardableResult
    func createPresetReminder(minutes: Int, title: String) -> ReminderItem {
        let item = engine.createReminder(
            title: title,
            durationSeconds: minutes * 60
        )
        soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
        return item
    }

    @discardableResult
    func createCalendarReminder(title: String, targetDate: Date, accent: AccentPreset = .mint) -> ReminderItem {
        let seconds = max(10, Int(targetDate.timeIntervalSinceNow.rounded()))
        let item = engine.createReminder(
            title: title,
            durationSeconds: seconds,
            targetDate: targetDate,
            accent: accent
        )
        soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
        return item
    }

    @discardableResult
    func createDialReminder(title: String) -> ReminderItem {
        createPresetReminder(minutes: selectedDialMinutes, title: title)
    }

    func togglePause(id: UUID) {
        engine.togglePause(id: id)
        soundHaptics.performHaptic(.generic, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
    }

    func adjustRemaining(id: UUID, deltaSeconds: Int) {
        engine.adjustRemaining(id: id, deltaSeconds: deltaSeconds)
        soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
    }

    func updateReminder(
        id: UUID,
        title: String? = nil,
        durationSeconds: Int? = nil,
        targetDate: Date? = nil,
        accent: AccentPreset? = nil
    ) {
        engine.updateReminder(
            id: id,
            title: title,
            durationSeconds: durationSeconds,
            targetDate: targetDate,
            accent: accent
        )
        soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        statusBarController?.refreshStatusTitle()
        refreshAlertPresentation()
    }

    func deleteReminder(id: UUID) {
        engine.deleteReminder(id: id)
        notifications.clearDelivered(for: id)
        statusBarController?.refreshStatusTitle()
        refreshAlertPresentation()
    }

    func resolveAlert(id: UUID, action: AlertResolutionAction) {
        if let preview = testPreviewReminder, preview.id == id {
            testPreviewReminder = nil
            soundHaptics.performHaptic(.levelChange, enabled: engine.settings.hapticsEnabled)
            refreshAlertPresentation()
            return
        }

        switch action {
        case .complete:
            engine.completeReminder(id: id)
            soundHaptics.performHaptic(.levelChange, enabled: engine.settings.hapticsEnabled)
        case .dismiss:
            engine.dismissReminder(id: id)
        case .snooze(let seconds):
            engine.snoozeReminder(id: id, addedSeconds: seconds)
            soundHaptics.performHaptic(.alignment, enabled: engine.settings.hapticsEnabled)
        }

        notifications.clearDelivered(for: id)
        statusBarController?.refreshStatusTitle()
        refreshAlertPresentation()
    }

    func previewFullScreenAlert() {
        let now = Date()
        testPreviewReminder = ReminderItem(
            title: "Sample Full-Screen Alert",
            durationSeconds: 15 * 60,
            createdAt: now.addingTimeInterval(-900),
            targetDate: now,
            status: .triggered,
            accent: .mint
        )
        soundHaptics.playChime(engine.settings.soundPreset, enabled: engine.settings.soundEnabled)
        soundHaptics.performHaptic(.levelChange, enabled: engine.settings.hapticsEnabled)
        refreshAlertPresentation()
    }

    func previewSound(_ preset: SoundPreset) {
        soundHaptics.playChime(preset, enabled: true)
    }

    func togglePresentationSafeMode() {
        engine.updateSettings { $0.presentationSafeMode.toggle() }
        soundHaptics.performHaptic(.generic, enabled: engine.settings.hapticsEnabled)
    }

    func updateGlobalShortcut(_ binding: HotkeyBinding) -> Bool {
        let success = hotkeyManager.register(binding: binding) { [weak self] in
            self?.togglePrimaryViaHotkey()
        }
        if success {
            lastHotkeyError = nil
            engine.updateSettings { $0.globalShortcut = binding }
        } else {
            lastHotkeyError = "Could not register \(binding.displayString). Another app or macOS shortcut may already own it."
            _ = hotkeyManager.register(binding: engine.settings.globalShortcut) { [weak self] in
                self?.togglePrimaryViaHotkey()
            }
        }
        return success
    }

    func registerCurrentHotkey() {
        let ok = hotkeyManager.register(binding: engine.settings.globalShortcut) { [weak self] in
            self?.togglePrimaryViaHotkey()
        }
        lastHotkeyError = ok ? nil : "Global hotkey \(engine.settings.globalShortcut.displayString) is unavailable (already claimed by another app)."
    }

    func updateAppleRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await remindersSync.requestAccess()
            engine.updateSettings { $0.appleRemindersSyncEnabled = granted }
        } else {
            engine.updateSettings { $0.appleRemindersSyncEnabled = false }
        }
    }

    func updateAppleCalendarEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await remindersSync.requestCalendarAccess()
            engine.updateSettings { $0.appleCalendarSyncEnabled = granted }
        } else {
            engine.updateSettings { $0.appleCalendarSyncEnabled = false }
        }
    }

    func reconcileAppleSyncNow() async {
        await engine.reconcileAllFromSyncProvider()
        statusBarController?.refreshStatusTitle()
        refreshAlertPresentation()
    }

    func requestIntentionalQuit() {
        let unfinished = engine.activeOrPausedReminders.count + engine.triggeredQueue.count
        guard unfinished > 0 && engine.settings.accountabilityWatchdogEnabled else {
            NSApp.terminate(nil)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Active Reminders Running (\(unfinished))"
        alert.informativeText = "SpacedOut's watchdog restarts missed timers across Mac restarts and force-quits. You can remove timers now, or allow quitting until your next reboot."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Until Reboot")
        alert.addButton(withTitle: "Remove Timers & Quit")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            watchdog.recordIntentionalQuitForCurrentBoot()
            engine.recordWatchdogEvent("User quit with \(unfinished) active timer(s); armed to resume on reboot")
            NSApp.terminate(nil)
        case .alertThirdButtonReturn:
            engine.removeAllActiveRemindersForQuit()
            watchdog.syncState(armed: false)
            NSApp.terminate(nil)
        default:
            break
        }
    }

    func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SpacedOut-Reminders.ics"
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .plainText]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content = ICSExporter.export(
            reminders: engine.activeOrPausedReminders,
            history: engine.history
        )
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportActivityLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SpacedOut-ActivityLog.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content = engine.exportActivityLogText()
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    var currentAlertItem: ReminderItem? {
        testPreviewReminder ?? engine.triggeredQueue.first
    }

    var activeAlertQueueCount: Int {
        if testPreviewReminder != nil { return 1 }
        return engine.triggeredQueue.count
    }

    private func handleTick() {
        tickCounter &+= 1
        evaluateTimersNow()
        if tickCounter % 60 == 0 {
            engine.touchLastSeen()
        }
    }

    private func evaluateTimersNow() {
        _ = engine.evaluateDueReminders()
        statusBarController?.refreshStatusTitle()
    }

    private func wireEngineCallbacks() {
        engine.onPreAlert = { [weak self] reminder in
            guard let self else { return }
            let secondsLeft = max(1, Int(ceil(reminder.remainingSeconds(at: Date()))))
            self.notifications.postPreAlertBanner(for: reminder, secondsRemaining: secondsLeft)
            self.soundHaptics.performHaptic(.alignment, enabled: self.engine.settings.hapticsEnabled)
        }

        engine.onTriggered = { [weak self] triggered in
            guard let self, !triggered.isEmpty else { return }
            self.handleTriggeredBatch(triggered)
        }

        engine.onRemindersChanged = { [weak self] in
            guard let self else { return }
            self.watchdog.syncState(armed: self.engine.shouldArmWatchdog)
        }

        engine.onSettingsChanged = { [weak self] settings in
            guard let self else { return }
            self.remindersSync.configure(
                remindersEnabled: settings.appleRemindersSyncEnabled,
                remindersListName: settings.appleRemindersListName,
                calendarEnabled: settings.appleCalendarSyncEnabled,
                calendarName: settings.appleCalendarName
            )
            self.floatingWidgetController?.applySettings(settings)
            self.utilityWindowManager?.applyTheme(settings.themeMode)
            self.statusBarController?.applySettings(settings)
            self.applyActivationPolicy(showDockIcon: settings.showDockIcon)
            self.watchdog.syncState(armed: self.engine.shouldArmWatchdog)
        }
    }

    private func handleTriggeredBatch(_ triggered: [ReminderItem]) {
        soundHaptics.playChime(engine.settings.soundPreset, enabled: engine.settings.soundEnabled)
        soundHaptics.performHaptic(.levelChange, enabled: engine.settings.hapticsEnabled)

        let shouldUseFullScreen = engine.settings.notificationStyle != .bannerOnly
            && !engine.settings.presentationSafeMode

        if shouldUseFullScreen {
            refreshAlertPresentation()
        } else {
            for item in triggered {
                notifications.postDueBanner(for: item)
            }
            if engine.settings.displayMode != .menuBarOnly {
                showFloatingWidget(focusInput: false)
            }
        }
    }

    func refreshAlertPresentation() {
        let shouldShowOverlay = currentAlertItem != nil
            && (testPreviewReminder != nil || (engine.settings.notificationStyle != .bannerOnly && !engine.settings.presentationSafeMode))

        if shouldShowOverlay {
            fullScreenAlertController?.showOrUpdate()
        } else {
            fullScreenAlertController?.dismissAll()
        }
    }
}
