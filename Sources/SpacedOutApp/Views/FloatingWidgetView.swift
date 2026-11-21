import SpacedOutCore
import SwiftUI

struct FloatingWidgetView: View {
    let isMenuBarPopover: Bool

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        switch coordinator.engine.settings.themeMode {
        case .system: return systemColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var widgetWidth: CGFloat {
        CGFloat(coordinator.engine.settings.widgetScale.width)
    }

    var body: some View {
        let scheme = effectiveColorScheme
        let inkPrimary = SpacedTheme.inkPrimary(for: scheme)
        let inkSecondary = SpacedTheme.inkSecondary(for: scheme)
        let inkMuted = SpacedTheme.inkMuted(for: scheme)
        let accent = SpacedTheme.accent(.mint, scheme: scheme)
        let activeList = coordinator.engine.activeOrPausedReminders

        VStack(alignment: .leading, spacing: 11) {
            headerBar(
                scheme: scheme,
                inkPrimary: inkPrimary,
                inkMuted: inkMuted,
                accent: accent,
                activeCount: activeList.count
            )

            if let preAlert = coordinator.engine.currentPreAlertReminder,
               !coordinator.engine.settings.presentationSafeMode {
                preAlertBanner(preAlert, scheme: scheme)
            }

            quickInputSection(
                scheme: scheme,
                inkPrimary: inkPrimary,
                inkSecondary: inkSecondary,
                inkMuted: inkMuted,
                accent: accent
            )

            presetsRow(
                scheme: scheme,
                inkPrimary: inkPrimary,
                inkSecondary: inkSecondary,
                accent: accent
            )

            if coordinator.isDialExpanded {
                HStack {
                    Spacer()
                    TactileDialView(
                        minutes: Binding(
                            get: { coordinator.selectedDialMinutes },
                            set: { coordinator.selectedDialMinutes = $0 }
                        ),
                        onMinuteTick: {
                            coordinator.soundHaptics.performHaptic(
                                .alignment,
                                enabled: coordinator.engine.settings.hapticsEnabled
                            )
                        },
                        onStartTapped: {
                            submitFromDial()
                        }
                    )
                    Spacer()
                }
                .padding(.vertical, 2)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }

            if activeList.isEmpty {
                idleFooter(
                    scheme: scheme,
                    inkMuted: inkMuted,
                    accent: accent
                )
            } else {
                timersListSection(activeList)
            }
        }
        .padding(14)
        .frame(width: widgetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active
                )

                SpacedTheme.widgetTintWash(for: scheme)

                if !isMenuBarPopover {
                    WindowDragSurface()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 1)
        )
        .preferredColorScheme(SpacedTheme.colorScheme(for: coordinator.engine.settings.themeMode))
        .onChange(of: coordinator.focusInputTrigger) { _, _ in
            isInputFocused = true
        }
        .onExitCommand {
            if isInputFocused {
                isInputFocused = false
            } else if !isMenuBarPopover {
                coordinator.hideFloatingWidget()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func headerBar(
        scheme: ColorScheme,
        inkPrimary: Color,
        inkMuted: Color,
        accent: Color,
        activeCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        coordinator.engine.settings.presentationSafeMode
                            ? SpacedTheme.urgencyAmber(for: scheme)
                            : (activeCount > 0 ? accent : inkMuted.opacity(0.45))
                    )
                    .frame(width: 7, height: 7)

                Text("SpacedOut")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(inkPrimary)

                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(accent.opacity(0.14)))
                }
            }

            Spacer()

            // Presentation / Call Safe Mode toggle
            Button {
                coordinator.togglePresentationSafeMode()
            } label: {
                Image(systemName: coordinator.engine.settings.presentationSafeMode ? "eye.slash.fill" : "eye")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(
                        coordinator.engine.settings.presentationSafeMode
                            ? SpacedTheme.urgencyAmber(for: scheme)
                            : inkMuted
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(
                            coordinator.engine.settings.presentationSafeMode
                                ? SpacedTheme.urgencyAmber(for: scheme).opacity(0.15)
                                : Color.clear
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(
                coordinator.engine.settings.presentationSafeMode
                    ? "Safe Mode On: Full-screen alerts downgraded to banners"
                    : "Safe Mode Off: Click to suppress full-screen takeovers during calls"
            )

            // Rotary Dial toggle
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                    coordinator.isDialExpanded.toggle()
                }
            } label: {
                Image(systemName: coordinator.isDialExpanded ? "dial.medium.fill" : "dial.medium")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(coordinator.isDialExpanded ? accent : inkMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(coordinator.isDialExpanded ? "Hide rotary dial" : "Show rotary dial (1–99m)")

            Button {
                coordinator.openHistoryWindow()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(inkMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Task History")

            Button {
                coordinator.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(inkMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Settings")

            if !isMenuBarPopover {
                Button {
                    coordinator.hideFloatingWidget()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(inkMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide widget (\(coordinator.engine.settings.globalShortcut.displayString))")
            }
        }
    }

    @ViewBuilder
    private func preAlertBanner(_ item: ReminderItem, scheme: ColorScheme) -> some View {
        let amber = SpacedTheme.urgencyAmber(for: scheme)
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let secs = max(1, Int(ceil(item.remainingSeconds(at: context.date))))
            HStack(spacing: 8) {
                Image(systemName: "bell.and.waves.left.and.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(amber)

                Text("\(item.displayTitle) in \(secs)s")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
                    .lineLimit(1)

                Spacer()

                Button("+5m") {
                    coordinator.adjustRemaining(id: item.id, deltaSeconds: 300)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(amber)

                Button("Done") {
                    coordinator.resolveAlert(id: item.id, action: .complete)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(SpacedTheme.accent(.mint, scheme: scheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(amber.opacity(scheme == .dark ? 0.16 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(amber.opacity(0.35), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func quickInputSection(
        scheme: ColorScheme,
        inkPrimary: Color,
        inkSecondary: Color,
        inkMuted: Color,
        accent: Color
    ) -> some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField(
                    "Remind me… e.g. tea 4m or call 4:30pm",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(inkPrimary)
                .focused($isInputFocused)
                .onSubmit {
                    submitQuickInput()
                }

                Button {
                    submitQuickInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help("Start reminder (Return)")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SpacedTheme.cardSurface(for: scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isInputFocused
                            ? accent.opacity(0.65)
                            : SpacedTheme.hairlineBorder(for: scheme),
                        lineWidth: 1
                    )
            )

            if !trimmed.isEmpty {
                let parsed = QuickInputParser.parse(
                    trimmed,
                    now: Date(),
                    fallbackDurationSeconds: coordinator.selectedDialMinutes * 60
                )
                HStack(spacing: 6) {
                    Image(systemName: parsed.matchedExplicitTime ? "sparkles" : "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)

                    Text(parsed.title.isEmpty ? "Quick Reminder" : parsed.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(inkSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text(parsed.previewBadge(at: Date()))
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func presetsRow(
        scheme: ColorScheme,
        inkPrimary: Color,
        inkSecondary: Color,
        accent: Color
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(coordinator.engine.settings.quickPresetsMinutes, id: \.self) { mins in
                Button {
                    submitPreset(minutes: mins)
                } label: {
                    Text("\(mins)m")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(inkPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(SpacedTheme.chipSurface(for: scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 0.9)
                        )
                }
                .buttonStyle(.plain)
                .help("Start \(mins)-minute reminder immediately")
            }

            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                    coordinator.isDialExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(coordinator.selectedDialMinutes)m")
                        .monospacedDigit()
                    Image(systemName: coordinator.isDialExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(accent.opacity(0.32), lineWidth: 0.9)
                )
            }
            .buttonStyle(.plain)
            .help("Toggle rotary time dial")
        }
    }

    @ViewBuilder
    private func timersListSection(_ list: [ReminderItem]) -> some View {
        if list.count <= 3 {
            VStack(spacing: 7) {
                ForEach(list) { item in
                    ReminderRowView(
                        item: item,
                        onTogglePause: { coordinator.togglePause(id: item.id) },
                        onAdjust: { delta in coordinator.adjustRemaining(id: item.id, deltaSeconds: delta) },
                        onRename: { newTitle in coordinator.updateReminder(id: item.id, title: newTitle) },
                        onComplete: { coordinator.resolveAlert(id: item.id, action: .complete) },
                        onDelete: { coordinator.deleteReminder(id: item.id) }
                    )
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(list) { item in
                        ReminderRowView(
                            item: item,
                            onTogglePause: { coordinator.togglePause(id: item.id) },
                            onAdjust: { delta in coordinator.adjustRemaining(id: item.id, deltaSeconds: delta) },
                            onRename: { newTitle in coordinator.updateReminder(id: item.id, title: newTitle) },
                            onComplete: { coordinator.resolveAlert(id: item.id, action: .complete) },
                            onDelete: { coordinator.deleteReminder(id: item.id) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 256)
        }
    }

    @ViewBuilder
    private func idleFooter(
        scheme: ColorScheme,
        inkMuted: Color,
        accent: Color
    ) -> some View {
        let stats = coordinator.engine.dailyStats()

        HStack {
            if stats.completedCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                    Text("\(stats.completedCount) done today · \(stats.totalFocusMinutes)m")
                        .font(.system(size: 11))
                        .foregroundStyle(inkMuted)
                }
            } else {
                Text("Click any preset or type a task above")
                    .font(.system(size: 11))
                    .foregroundStyle(inkMuted)
            }

            Spacer()

            Text(coordinator.engine.settings.globalShortcut.displayString)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(inkMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(SpacedTheme.chipSurface(for: scheme))
                )
        }
        .padding(.top, 2)
    }

    // MARK: - Submission Helpers

    @MainActor
    private func submitQuickInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            coordinator.createDialReminder(title: "")
        } else {
            coordinator.createQuickReminder(from: trimmed)
            inputText = ""
        }
    }

    @MainActor
    private func submitPreset(minutes: Int) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.createPresetReminder(minutes: minutes, title: trimmed)
        inputText = ""
    }

    @MainActor
    private func submitFromDial() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.createDialReminder(title: trimmed)
        inputText = ""
    }
}
