import SpacedOutCore
import SwiftUI

private struct WidgetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 {
            value = next
        }
    }
}

struct FloatingWidgetView: View {
    let isMenuBarPopover: Bool
    var onPreferredSizeChange: ((CGSize) -> Void)? = nil

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText: String = ""
    @State private var showCalendarPopover: Bool = false
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

    private var glassOpacity: Double {
        min(1.0, max(0.15, coordinator.engine.settings.widgetOpacity))
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
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WidgetContentSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(WidgetContentSizeKey.self) { newSize in
            if newSize.width > 0 && newSize.height > 0 {
                onPreferredSizeChange?(newSize)
            }
        }
        .background {
            let glass = glassOpacity

            ZStack {
                VisualEffectView(
                    material: .popover,
                    blendingMode: .behindWindow,
                    state: .active,
                    isHidden: glass < 0.28
                )

                SpacedTheme.widgetGlassWash(for: scheme, opacity: glass)
                SpacedTheme.widgetSolidCover(for: scheme, opacity: glass)

                if !isMenuBarPopover {
                    WindowDragSurface()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SpacedTheme.hairlineBorder(for: scheme, glassOpacity: glassOpacity), lineWidth: 1)
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

    @ViewBuilder
    private func headerBar(
        scheme: ColorScheme,
        inkPrimary: Color,
        inkMuted: Color,
        accent: Color,
        activeCount: Int
    ) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                BrandLogoMark(
                    size: 16,
                    color: coordinator.engine.settings.presentationSafeMode
                        ? SpacedTheme.urgencyAmber(for: scheme)
                        : (activeCount > 0 ? accent : inkPrimary)
                )

                Text("SpacedOut")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(inkPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer(minLength: 4)

            HeaderIconButton(
                systemName: coordinator.engine.settings.presentationSafeMode ? "eye.slash.fill" : "eye",
                tint: coordinator.engine.settings.presentationSafeMode
                    ? SpacedTheme.urgencyAmber(for: scheme)
                    : inkMuted,
                isActive: coordinator.engine.settings.presentationSafeMode,
                scheme: scheme,
                helpText: coordinator.engine.settings.presentationSafeMode
                    ? "Safe Mode On: Full-screen alerts downgraded to banners"
                    : "Safe Mode Off: Click to suppress full-screen takeovers during calls"
            ) {
                coordinator.togglePresentationSafeMode()
            }

            HeaderIconButton(
                systemName: coordinator.isDialExpanded ? "dial.medium.fill" : "dial.medium",
                tint: coordinator.isDialExpanded ? accent : inkMuted,
                isActive: coordinator.isDialExpanded,
                scheme: scheme,
                helpText: coordinator.isDialExpanded ? "Hide rotary dial" : "Show rotary dial (1–99m)"
            ) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                    coordinator.isDialExpanded.toggle()
                }
            }

            HeaderIconButton(
                systemName: "clock.arrow.circlepath",
                tint: inkMuted,
                isActive: false,
                scheme: scheme,
                helpText: "Task History & Activity Log"
            ) {
                coordinator.openHistoryWindow()
            }

            HeaderIconButton(
                systemName: "gearshape",
                tint: inkMuted,
                isActive: false,
                scheme: scheme,
                helpText: "Settings"
            ) {
                coordinator.openSettingsWindow()
            }

            if !isMenuBarPopover {
                HeaderIconButton(
                    systemName: "minus",
                    tint: inkMuted,
                    isActive: false,
                    scheme: scheme,
                    helpText: "Hide widget (\(coordinator.engine.settings.globalShortcut.displayString))"
                ) {
                    coordinator.hideFloatingWidget()
                }
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

                Button {
                    coordinator.adjustRemaining(id: item.id, deltaSeconds: 300)
                } label: {
                    Text("+5m")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(amber.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())

                Button {
                    coordinator.resolveAlert(id: item.id, action: .complete)
                } label: {
                    Text("Done")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(SpacedTheme.accent(.mint, scheme: scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(SpacedTheme.accent(.mint, scheme: scheme).opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
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
            HStack(spacing: 6) {
                TextField(
                    "Remind me… tea 4m, tomorrow 9am",
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
                    coordinator.ensureActivePanelKey()
                    showCalendarPopover = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(showCalendarPopover ? accent : inkMuted)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(
                                showCalendarPopover
                                    ? accent.opacity(0.14)
                                    : SpacedTheme.chipSurface(for: scheme, glassOpacity: glassOpacity)
                            )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Schedule on calendar")
                .popover(isPresented: $showCalendarPopover, arrowEdge: .bottom) {
                    CalendarSchedulePopover(
                        initialTitle: trimmed,
                        scheme: scheme,
                        syncSummary: calendarSyncNote,
                        onSchedule: { title, date, chosenAccent in
                            coordinator.createCalendarReminder(
                                title: title,
                                targetDate: date,
                                accent: chosenAccent
                            )
                            inputText = ""
                            showCalendarPopover = false
                        },
                        onCancel: {
                            showCalendarPopover = false
                        }
                    )
                }

                Button {
                    submitQuickInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Start reminder (Return)")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SpacedTheme.cardSurface(for: scheme, glassOpacity: glassOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isInputFocused
                            ? accent.opacity(0.65)
                            : SpacedTheme.hairlineBorder(for: scheme, glassOpacity: glassOpacity),
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

    private var calendarSyncNote: String {
        let rem = coordinator.engine.settings.appleRemindersSyncEnabled
        let cal = coordinator.engine.settings.appleCalendarSyncEnabled
        if rem && cal { return "Syncs to Apple Reminders & Calendar" }
        if rem { return "Syncs to Apple Reminders" }
        if cal { return "Syncs to Apple Calendar" }
        return "Local only (Apple sync off in Settings)"
    }

    @ViewBuilder
    private func presetsRow(
        scheme: ColorScheme,
        inkPrimary: Color,
        accent: Color
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(coordinator.engine.settings.quickPresetsMinutes, id: \.self) { mins in
                PresetChipButton(
                    label: "\(mins)m",
                    scheme: scheme,
                    inkPrimary: inkPrimary,
                    glassOpacity: glassOpacity
                ) {
                    submitPreset(minutes: mins)
                }
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .help("Toggle rotary time dial")
        }
    }

    @ViewBuilder
    private func timersListSection(_ list: [ReminderItem]) -> some View {
        if list.count <= 3 {
            VStack(spacing: 7) {
                ForEach(list) { item in
                    rowView(for: item)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(list) { item in
                        rowView(for: item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 256)
        }
    }

    private func rowView(for item: ReminderItem) -> some View {
        ReminderRowView(
            item: item,
            glassOpacity: glassOpacity,
            onTogglePause: { coordinator.togglePause(id: item.id) },
            onAdjust: { delta in coordinator.adjustRemaining(id: item.id, deltaSeconds: delta) },
            onEdit: { title, duration, targetDate, accent in
                coordinator.updateReminder(
                    id: item.id,
                    title: title,
                    durationSeconds: duration,
                    targetDate: targetDate,
                    accent: accent
                )
            },
            onPreparePopover: { coordinator.ensureActivePanelKey() },
            onComplete: { coordinator.resolveAlert(id: item.id, action: .complete) },
            onDelete: { coordinator.deleteReminder(id: item.id) }
        )
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
                        .fill(SpacedTheme.chipSurface(for: scheme, glassOpacity: glassOpacity))
                )
        }
        .padding(.top, 2)
    }

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

private struct CalendarSchedulePopover: View {
    let scheme: ColorScheme
    let syncSummary: String
    let onSchedule: (String, Date, AccentPreset) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var targetDate: Date
    @State private var selectedAccent: AccentPreset = .mint

    init(
        initialTitle: String,
        scheme: ColorScheme,
        syncSummary: String,
        onSchedule: @escaping (String, Date, AccentPreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.scheme = scheme
        self.syncSummary = syncSummary
        self.onSchedule = onSchedule
        self.onCancel = onCancel
        _title = State(initialValue: initialTitle)
        _targetDate = State(initialValue: Date().addingTimeInterval(3600))
    }

    var body: some View {
        let accent = SpacedTheme.accent(selectedAccent, scheme: scheme)

        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Schedule Reminder")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
            }

            TextField("Reminder title…", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { scheduleNow() }

            HStack(spacing: 6) {
                Button("+1h") { targetDate = Date().addingTimeInterval(3600) }
                Button("Tonight 8pm") { targetDate = nextOccurrence(hour: 20, minute: 0) }
                Button("Tomorrow 9am") { targetDate = tomorrowOccurrence(hour: 9, minute: 0) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            DatePicker(
                "Date",
                selection: $targetDate,
                in: Date()...,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)

            DatePicker(
                "Time",
                selection: $targetDate,
                displayedComponents: [.hourAndMinute]
            )
            .font(.system(size: 12))

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
                Text(syncSummary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Schedule") {
                    scheduleNow()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 292)
    }

    private func scheduleNow() {
        let safeDate = max(Date().addingTimeInterval(15), targetDate)
        onSchedule(title, safeDate, selectedAccent)
    }

    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let candidate = cal.date(from: comps), candidate > now.addingTimeInterval(60) {
            return candidate
        }
        return tomorrowOccurrence(hour: hour, minute: minute)
    }

    private func tomorrowOccurrence(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps) ?? Date().addingTimeInterval(86400)
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let tint: Color
    let isActive: Bool
    let scheme: ColorScheme
    let helpText: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        isActive
                            ? tint.opacity(0.15)
                            : (isHovered ? SpacedTheme.chipSurface(for: scheme) : Color.clear)
                    )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}

private struct PresetChipButton: View {
    let label: String
    let scheme: ColorScheme
    let inkPrimary: Color
    let glassOpacity: Double
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(inkPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isHovered
                                ? SpacedTheme.cardSurface(for: scheme, glassOpacity: glassOpacity)
                                : SpacedTheme.chipSurface(for: scheme, glassOpacity: glassOpacity)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SpacedTheme.hairlineBorder(for: scheme, glassOpacity: glassOpacity), lineWidth: 0.9)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovered = $0 }
    }
}
