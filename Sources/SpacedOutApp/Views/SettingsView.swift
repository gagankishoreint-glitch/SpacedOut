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
                    Label("Reminders & Data", systemImage: "checklist")
                }
        }
        .padding(18)
        .frame(width: 570, height: 510)
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
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { coordinator.engine.settings.widgetOpacity },
                                set: { val in coordinator.engine.updateSettings { $0.widgetOpacity = val } }
                            ),
                            in: 0.72...1.0
                        )
                        .labelsHidden()
                        .frame(width: 170)

                        Text("\(Int((coordinator.engine.settings.widgetOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
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

    var body: some View {
        Form {
            Section("Apple Reminders Sync") {
                Toggle("Sync New Reminders with Apple Reminders", isOn: Binding(
                    get: { coordinator.engine.settings.appleRemindersSyncEnabled },
                    set: { enabled in
                        Task { @MainActor in
                            await coordinator.updateAppleRemindersEnabled(enabled)
                        }
                    }
                ))

                LabeledContent("Permission Status") {
                    Text(coordinator.remindersSync.authState.label)
                        .foregroundStyle(
                            coordinator.remindersSync.authState == .authorized ? .green : .secondary
                        )
                }

                if coordinator.remindersSync.authState == .notDetermined {
                    LabeledContent("Authorization") {
                        Button("Request Reminders Access") {
                            Task { @MainActor in
                                _ = await coordinator.remindersSync.requestAccess()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if coordinator.remindersSync.authState == .denied || coordinator.remindersSync.authState == .writeOnly {
                    LabeledContent("Authorization") {
                        Button("Open Privacy Settings…") {
                            coordinator.remindersSync.openSystemRemindersPrivacy()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent("Target List Name") {
                    HStack(spacing: 8) {
                        TextField("", text: $listNameDraft, prompt: Text("SpacedOut"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 155)
                            .onSubmit { applyListName() }
                        Button("Save") { applyListName() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if let syncError = coordinator.remindersSync.lastSyncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Export & Storage") {
                LabeledContent("Calendar Export (.ics)") {
                    Button("Export Reminders & History…") {
                        coordinator.exportICS()
                    }
                    .buttonStyle(.bordered)
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
        }
        .confirmationDialog(
            "Reset all SpacedOut timers, history, and settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                coordinator.engine.resetAllData()
                listNameDraft = coordinator.engine.settings.appleRemindersListName
                coordinator.applyDisplayMode(coordinator.engine.settings.displayMode)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @MainActor
    private func applyListName() {
        let trimmed = listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "SpacedOut" : trimmed
        listNameDraft = resolved
        coordinator.engine.updateSettings { $0.appleRemindersListName = resolved }
    }
}
