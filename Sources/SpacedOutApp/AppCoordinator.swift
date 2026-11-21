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
    private var didStart = false

    init() {
        let engine = TimerEngine()
        let remindersSync = AppleRemindersService()
        remindersSync.configureTargetList(engine.settings.appleRemindersListName)
        engine.attachSyncProvider(remindersSync)

        self.engine = engine
        self.soundHaptics = SoundHapticsService()
        self.remindersSync = remindersSync
        self.notifications = NotificationService()
        self.hotkeyManager = GlobalHotkeyManager()
        self.selectedDialMinutes = engine.settings.defaultDurationMinutes

        wireEngineCallbacks()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

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
        Task { @MainActor in
            await notifications.requestPermissionIfNeeded()
        }

        floatingWidgetController = FloatingWidgetController(coordinator: self)
        fullScreenAlertController = FullScreenAlertController(coordinator: self)
        statusBarController = StatusBarController(coordinator: self)
        utilityWindowManager = UtilityWindowManager(coordinator: self)

        registerCurrentHotkey()
        applyDisplayMode(engine.settings.displayMode, initialLaunch: true)

        // Wake & timer tick resilience
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTimersNow()
            }
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTimersNow()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer

        evaluateTimersNow()
        refreshAlertPresentation()
    }

    func shutdown() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        hotkeyManager.shutdown()
    }

    // MARK: - Window & UI Presentation

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

    // MARK: - Actions

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

    func updateReminder(id: UUID, title: String? = nil, durationSeconds: Int? = nil) {
        engine.updateReminder(id: id, title: title, durationSeconds: durationSeconds)
        statusBarController?.refreshStatusTitle()
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
            // Restore previous working shortcut
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

    // MARK: - Internal Engine Wiring

    var currentAlertItem: ReminderItem? {
        testPreviewReminder ?? engine.triggeredQueue.first
    }

    var activeAlertQueueCount: Int {
        if testPreviewReminder != nil { return 1 }
        return engine.triggeredQueue.count
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

        engine.onSettingsChanged = { [weak self] settings in
            guard let self else { return }
            self.remindersSync.configureTargetList(settings.appleRemindersListName)
            self.floatingWidgetController?.applySettings(settings)
            self.utilityWindowManager?.applyTheme(settings.themeMode)
            self.statusBarController?.applySettings(settings)
            self.applyActivationPolicy(showDockIcon: settings.showDockIcon)
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
