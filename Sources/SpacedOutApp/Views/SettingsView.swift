import SpacedOutCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "sparkles")
                }

            AlertsSettingsTab()
                .tabItem {
                    Label("Alerts & Sound", systemImage: "bell.badge")
                }

            RemindersDataSettingsTab()
                .tabItem {
                    Label("Sync & System", systemImage: "arrow.triangle.2.circlepath.circle")
                }
        }
        .padding(18)
        .frame(width: 600, height: 610)
        .preferredColorScheme(SpacedTheme.colorScheme(for: coordinator.engine.settings.themeMode))
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var presetsText: String = ""

    var body: some View {
        Form {
            Section("Workflow Mode") {
                Picker("Display Mode", selection: Binding(
                    get: { coordinator.engine.settings.displayMode },
                    set: { newMode in
                        coordinator.engine.updateSettings { $0.displayMode = newMode }
                        coordinator.applyDisplayMode(newMode)
                    }
                )) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(coordinator.engine.settings.displayMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Presets & Hotkey") {
                LabeledContent("Quick Preset Minutes") {
                    HStack(spacing: 8) {
                        TextField("", text: $presetsText, prompt: Text("5, 10, 15, 25"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .onSubmit { applyPresetsText() }
                        Button("Apply") { applyPresetsText() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Stepper(
                    "Default Dial Duration: \(coordinator.engine.settings.defaultDurationMinutes) min",
                    value: Binding(
                        get: { coordinator.engine.settings.defaultDurationMinutes },
                        set: { val in
                            coordinator.engine.updateSettings { $0.defaultDurationMinutes = val }
                            coordinator.selectedDialMinutes = val
                        }
                    ),
                    in: 1...240
                )

                LabeledContent("Toggle Global Shortcut") {
                    ShortcutRecorderView(
                        currentBinding: coordinator.engine.settings.globalShortcut,
                        onCaptured: { binding in
                            coordinator.updateGlobalShortcut(binding)
                        },
                        onResetDefault: {
                            _ = coordinator.updateGlobalShortcut(.defaultToggleWidget)
                        }
                    )
                }

                if let error = coordinator.lastHotkeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { coordinator.engine.settings.launchAtLogin },
                    set: { enabled in
                        let ok = LaunchAtLoginService.setEnabled(enabled)
                        coordinator.engine.updateSettings {
                            $0.launchAtLogin = ok ? enabled : false
                        }
                    }
                ))
                .disabled(!LaunchAtLoginService.isAvailableInCurrentBundle)

                if !LaunchAtLoginService.isAvailableInCurrentBundle {
                    Text("Launch at Login activates when running the built SpacedOut.app bundle (via make run).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            presetsText = coordinator.engine.settings.quickPresetsMinutes
                .map(String.init)
                .joined(separator: ", ")
        }
    }

    @MainActor
    private func applyPresetsText() {
        let parsed = presetsText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { max(1, min(999, $0)) }
            .prefix(5)
        let finalPresets = parsed.isEmpty ? [5, 10, 15, 25] : Array(parsed)
        coordinator.engine.updateSettings { $0.quickPresetsMinutes = finalPresets }
        presetsText = finalPresets.map(String.init).joined(separator: ", ")
    }
}

private struct AppearanceSettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section("Theme & Glass") {
                Picker("Theme", selection: Binding(
                    get: { coordinator.engine.settings.themeMode },
                    set: { mode in coordinator.engine.updateSettings { $0.themeMode = mode } }
                )) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Widget Size", selection: Binding(
                    get: { coordinator.engine.settings.widgetScale },
                    set: { scale in coordinator.engine.updateSettings { $0.widgetScale = scale } }
                )) {
                    ForEach(WidgetScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }

                LabeledContent("Glass Opacity") {
                    HStack(spacing: 8) {
                        Text("Sheer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: { coordinator.engine.settings.widgetOpacity },
                                set: { val in coordinator.engine.updateSettings { $0.widgetOpacity = val } }
                            ),
                            in: 0.15...1.0
                        )
                        .labelsHidden()
                        .frame(width: 145)

                        Text("Solid")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("\(Int((coordinator.engine.settings.widgetOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                Text("Adjusts glass translucency from sheer crystal to solid while keeping text sharp.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window Behavior") {
                Toggle("Keep Floating Widget Always on Top", isOn: Binding(
                    get: { coordinator.engine.settings.alwaysOnTop },
                    set: { val in coordinator.engine.updateSettings { $0.alwaysOnTop = val } }
                ))

                Toggle("Show App Icon in Dock", isOn: Binding(
                    get: { coordinator.engine.settings.showDockIcon },
                    set: { val in coordinator.engine.updateSettings { $0.showDockIcon = val } }
                ))

                LabeledContent("Widget Screen Placement") {
                    Button("Reset to Top-Right") {
                        coordinator.resetWidgetPosition()
                        coordinator.showFloatingWidget(focusInput: false)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertsSettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section("Alert Style") {
                Picker("When Timer Expires", selection: Binding(
                    get: { coordinator.engine.settings.notificationStyle },
                    set: { style in coordinator.engine.updateSettings { $0.notificationStyle = style } }
                )) {
                    ForEach(NotificationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Text(coordinator.engine.settings.notificationStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if coordinator.engine.settings.notificationStyle == .fullScreenWithPreAlert {
                    Stepper(
                        "Pre-Alert Lead Time: \(coordinator.engine.settings.preAlertSeconds)s",
                        value: Binding(
                            get: { coordinator.engine.settings.preAlertSeconds },
                            set: { val in coordinator.engine.updateSettings { $0.preAlertSeconds = val } }
                        ),
                        in: 10...120,
                        step: 5
                    )
                }

                Toggle("Presentation / Call Safe Mode", isOn: Binding(
                    get: { coordinator.engine.settings.presentationSafeMode },
                    set: { val in coordinator.engine.updateSettings { $0.presentationSafeMode = val } }
                ))

                LabeledContent("Preview Overlay") {
                    Button("Test Full-Screen Alert") {
                        coordinator.previewFullScreenAlert()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Audio & Haptics") {
                Toggle("Play Sound on Alert", isOn: Binding(
                    get: { coordinator.engine.settings.soundEnabled },
                    set: { val in coordinator.engine.updateSettings { $0.soundEnabled = val } }
                ))

                LabeledContent("Chime Sound") {
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { coordinator.engine.settings.soundPreset },
                            set: { preset in coordinator.engine.updateSettings { $0.soundPreset = preset } }
                        )) {
                            ForEach(SoundPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 155)

                        Button("Preview") {
                            coordinator.previewSound(coordinator.engine.settings.soundPreset)
                        }
                        .buttonStyle(.bordered)
                        .disabled(coordinator.engine.settings.soundPreset == .silent)
                    }
                }

                Toggle("Trackpad Haptic Feedback", isOn: Binding(
                    get: { coordinator.engine.settings.hapticsEnabled },
                    set: { val in coordinator.engine.updateSettings { $0.hapticsEnabled = val } }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct RemindersDataSettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showResetConfirmation = false
    @State private var listNameDraft = ""
    @State private var calendarNameDraft = ""

    var body: some View {
        Form {
            Section("Apple Reminders & Calendar Sync") {
                Toggle("Sync Timers with Apple Reminders", isOn: Binding(
                    get: { coordinator.engine.settings.appleRemindersSyncEnabled },
                    set: { enabled in
                        Task { @MainActor in
                            await coordinator.updateAppleRemindersEnabled(enabled)
                        }
                    }
                ))

                LabeledContent("Reminders Access") {
                    HStack(spacing: 8) {
                        Text(coordinator.remindersSync.authState.label)
                            .foregroundStyle(
                                coordinator.remindersSync.authState == .authorized ? .green : .secondary
                            )
                        if coordinator.remindersSync.authState == .notDetermined {
                            Button("Allow…") {
                                Task { @MainActor in
                                    _ = await coordinator.remindersSync.requestAccess()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if coordinator.remindersSync.authState == .denied || coordinator.remindersSync.authState == .writeOnly {
                            Button("Open Privacy…") {
                                coordinator.remindersSync.openSystemRemindersPrivacy()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("Reminders List") {
                    HStack(spacing: 8) {
                        TextField("", text: $listNameDraft, prompt: Text("SpacedOut"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 145)
                            .onSubmit { applyListName() }
                        Button("Apply") { applyListName() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Toggle("Sync Scheduled Timers with Apple Calendar", isOn: Binding(
                    get: { coordinator.engine.settings.appleCalendarSyncEnabled },
                    set: { enabled in
                        Task { @MainActor in
                            await coordinator.updateAppleCalendarEnabled(enabled)
                        }
                    }
                ))

                LabeledContent("Calendar Access") {
                    HStack(spacing: 8) {
                        Text(coordinator.remindersSync.calendarAuthState.label)
                            .foregroundStyle(
                                coordinator.remindersSync.calendarAuthState == .authorized ? .green : .secondary
                            )
                        if coordinator.remindersSync.calendarAuthState == .notDetermined {
                            Button("Allow…") {
                                Task { @MainActor in
                                    _ = await coordinator.remindersSync.requestCalendarAccess()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if coordinator.remindersSync.calendarAuthState == .denied || coordinator.remindersSync.calendarAuthState == .writeOnly {
                            Button("Open Privacy…") {
                                coordinator.remindersSync.openSystemCalendarPrivacy()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("Calendar Name") {
                    HStack(spacing: 8) {
                        TextField("", text: $calendarNameDraft, prompt: Text("SpacedOut"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 145)
                            .onSubmit { applyCalendarName() }
                        Button("Apply") { applyCalendarName() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                LabeledContent("Two-Way Sync") {
                    Button("Sync Changes Now") {
                        Task { @MainActor in
                            await coordinator.reconcileAppleSyncNow()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if let syncError = coordinator.remindersSync.lastSyncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Accountability & Screen Time") {
                Toggle("Keep Active Timers Alive Across Crashes & Restarts", isOn: Binding(
                    get: { coordinator.engine.settings.accountabilityWatchdogEnabled },
                    set: { enabled in
                        coordinator.engine.updateSettings { $0.accountabilityWatchdogEnabled = enabled }
                    }
                ))

                LabeledContent("Watchdog Status") {
                    Text(watchdogStatusLabel)
                        .foregroundStyle(coordinator.engine.shouldArmWatchdog ? .green : .secondary)
                }

                LabeledContent("Apple Screen Time") {
                    Button("Open Screen Time…") {
                        coordinator.openScreenTimeSettings()
                    }
                    .buttonStyle(.bordered)
                }

                LabeledContent("Screen Time Panes") {
                    HStack(spacing: 6) {
                        Button("Always Allowed…") {
                            coordinator.openScreenTimeSettings(subpath: "always-allowed")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Downtime…") {
                            coordinator.openScreenTimeSettings(subpath: "downtime")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("App Limits…") {
                            coordinator.openScreenTimeSettings(subpath: "app-limits")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("Pair focus timers with Screen Time in System Settings (Downtime & App Limits panes require App & Website Activity enabled).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export & Storage") {
                LabeledContent("Calendar Export (.ics)") {
                    Button("Export Reminders & History…") {
                        coordinator.exportICS()
                    }
                    .buttonStyle(.bordered)
                }

                LabeledContent("User Activity Log (.txt)") {
                    Button("Export Activity Log…") {
                        coordinator.exportActivityLog()
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.activityLog.isEmpty)
                }

                LabeledContent("Reset Local App Data") {
                    Button("Reset Everything", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            listNameDraft = coordinator.engine.settings.appleRemindersListName
            calendarNameDraft = coordinator.engine.settings.appleCalendarName
        }
        .confirmationDialog(
            "Reset all SpacedOut timers, history, and settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                coordinator.engine.resetAllData()
                listNameDraft = coordinator.engine.settings.appleRemindersListName
                calendarNameDraft = coordinator.engine.settings.appleCalendarName
                coordinator.applyDisplayMode(coordinator.engine.settings.displayMode)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var watchdogStatusLabel: String {
        if !coordinator.watchdog.isSupportedInCurrentBundle {
            return "Requires .app Bundle (make run)"
        }
        if !coordinator.engine.settings.accountabilityWatchdogEnabled {
            return "Disabled"
        }
        return coordinator.engine.shouldArmWatchdog ? "Armed (Active Timers)" : "Standby (No Active Timers)"
    }

    @MainActor
    private func applyListName() {
        let trimmed = listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "SpacedOut" : trimmed
        listNameDraft = resolved
        coordinator.engine.updateSettings { $0.appleRemindersListName = resolved }
    }

    @MainActor
    private func applyCalendarName() {
        let trimmed = calendarNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "SpacedOut" : trimmed
        calendarNameDraft = resolved
        coordinator.engine.updateSettings { $0.appleCalendarName = resolved }
    }
}
