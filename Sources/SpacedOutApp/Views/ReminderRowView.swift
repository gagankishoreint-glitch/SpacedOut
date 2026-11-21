import SpacedOutCore
import SwiftUI

struct ReminderRowView: View {
    let item: ReminderItem
    var glassOpacity: Double = 0.78
    var onTogglePause: () -> Void
    var onAdjust: (Int) -> Void
    var onEdit: (String?, Int?, Date?, AccentPreset?) -> Void
    var onPreparePopover: () -> Void
    var onComplete: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var showEditPopover = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            let remaining = item.remainingSeconds(at: now)
            let progress = item.progressFraction(at: now)
            let isUrgent = item.status == .active && remaining <= 30
            let isPaused = item.status == .paused

            let ringColor: Color = {
                if isPaused { return SpacedTheme.urgencyAmber(for: colorScheme) }
                if isUrgent { return SpacedTheme.overdueCoral(for: colorScheme) }
                return SpacedTheme.accent(item.accent, scheme: colorScheme)
            }()

            VStack(spacing: 8) {
                HStack(spacing: 11) {
                    Button(action: onTogglePause) {
                        ZStack {
                            Circle()
                                .stroke(ringColor.opacity(0.20), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))

                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(ringColor)
                                .opacity(isHovered || isPaused ? 1 : 0.42)
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help(isPaused ? "Resume timer" : "Pause timer")

                    VStack(alignment: .leading, spacing: 2) {
                        if isEditingTitle {
                            TextField("Reminder title", text: $draftTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SpacedTheme.inkPrimary(for: colorScheme))
                                .focused($titleFieldFocused)
                                .onSubmit { commitRename() }
                                .onExitCommand { cancelRename() }
                                .onChange(of: titleFieldFocused) { _, focused in
                                    if !focused && isEditingTitle {
                                        commitRename()
                                    }
                                }
                        } else {
                            HStack(spacing: 5) {
                                Text(item.displayTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(SpacedTheme.inkPrimary(for: colorScheme))
                                    .lineLimit(1)

                                if item.snoozeCount > 0 {
                                    Text("+\(item.snoozeCount)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(SpacedTheme.urgencyAmber(for: colorScheme))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule()
                                                .fill(SpacedTheme.urgencyAmber(for: colorScheme).opacity(0.14))
                                        )
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPreparePopover()
                                draftTitle = item.title
                                isEditingTitle = true
                                Task { @MainActor in
                                    titleFieldFocused = true
                                }
                            }
                            .help("Click to rename, or use Edit below for date & time")
                        }

                        HStack(spacing: 5) {
                            if isPaused {
                                Text("Paused")
                                    .foregroundStyle(SpacedTheme.urgencyAmber(for: colorScheme))
                            } else {
                                Text("Ends \(item.formattedTargetDate(relativeTo: now))")
                                    .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                                    .lineLimit(1)
                            }

                            if item.externalReminderID != nil {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                                    .help("Synced to Apple Reminders")
                            }

                            if item.externalCalendarEventID != nil {
                                Image(systemName: "calendar")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                                    .help("Synced to Apple Calendar")
                            }
                        }
                        .font(.system(size: 10.5))
                    }

                    Spacer(minLength: 6)

                    Text(item.formattedRemaining(at: now))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            isUrgent
                                ? SpacedTheme.overdueCoral(for: colorScheme)
                                : SpacedTheme.inkPrimary(for: colorScheme)
                        )
                }

                if isHovered || showEditPopover {
                    HStack(spacing: 5) {
                        QuickAdjustPill(label: "-1m", glassOpacity: glassOpacity) { onAdjust(-60) }
                        QuickAdjustPill(label: "+1m", glassOpacity: glassOpacity) { onAdjust(60) }
                        QuickAdjustPill(label: "+5m", glassOpacity: glassOpacity) { onAdjust(300) }

                        Spacer()

                        Button {
                            onPreparePopover()
                            showEditPopover = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(SpacedTheme.inkSecondary(for: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule()
                                        .fill(SpacedTheme.chipSurface(for: colorScheme, glassOpacity: glassOpacity))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(SpacedTheme.hairlineBorder(for: colorScheme, glassOpacity: glassOpacity), lineWidth: 0.7)
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .help("Edit reminder title, duration, or calendar time")

                        Button(action: onComplete) {
                            Label("Done", systemImage: "checkmark")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(SpacedTheme.accent(.mint, scheme: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule()
                                        .fill(SpacedTheme.accent(.mint, scheme: colorScheme).opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .help("Mark complete now")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(SpacedTheme.chipSurface(for: colorScheme, glassOpacity: glassOpacity)))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .help("Cancel & remove timer")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SpacedTheme.cardSurface(for: colorScheme, glassOpacity: glassOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isUrgent
                            ? SpacedTheme.overdueCoral(for: colorScheme).opacity(0.45)
                            : SpacedTheme.hairlineBorder(for: colorScheme, glassOpacity: glassOpacity),
                        lineWidth: 1
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
            .popover(isPresented: $showEditPopover, arrowEdge: .leading) {
                ReminderEditPopover(
                    item: item,
                    scheme: colorScheme,
                    onSave: { newTitle, newDuration, newDate, newAccent in
                        onEdit(newTitle, newDuration, newDate, newAccent)
                        showEditPopover = false
                    },
                    onCancel: {
                        showEditPopover = false
                    }
                )
            }
        }
    }

    private func commitRename() {
        isEditingTitle = false
        onEdit(draftTitle, nil, nil, nil)
    }

    private func cancelRename() {
        isEditingTitle = false
        draftTitle = item.title
    }
}

private struct ReminderEditPopover: View {
    enum EditScheduleMode: String, CaseIterable, Identifiable {
        case duration = "Duration"
        case calendar = "Date & Time"
        var id: String { rawValue }
    }

    let item: ReminderItem
    let scheme: ColorScheme
    let onSave: (String?, Int?, Date?, AccentPreset?) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var mode: EditScheduleMode
    @State private var durationMinutes: Int
    @State private var scheduledDate: Date
    @State private var selectedAccent: AccentPreset

    init(
        item: ReminderItem,
        scheme: ColorScheme,
        onSave: @escaping (String?, Int?, Date?, AccentPreset?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.scheme = scheme
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: item.title)
        let remSeconds = max(60, Int(item.remainingSeconds(at: Date()).rounded()))
        let remMinutes = max(1, Int((Double(remSeconds) / 60.0).rounded()))
        _durationMinutes = State(initialValue: remMinutes)
        _scheduledDate = State(initialValue: max(Date().addingTimeInterval(60), item.targetDate))
        _mode = State(initialValue: remSeconds >= 7200 ? .calendar : .duration)
        _selectedAccent = State(initialValue: item.accent)
    }

    var body: some View {
        let accent = SpacedTheme.accent(selectedAccent, scheme: scheme)

        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Reminder")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))

            TextField("Reminder title…", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveChanges() }

            Picker("", selection: $mode) {
                ForEach(EditScheduleMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if mode == .duration {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Remaining:")
                            .font(.system(size: 12))
                            .foregroundStyle(SpacedTheme.inkSecondary(for: scheme))
                        Spacer()
                        Stepper("\(durationMinutes) min", value: $durationMinutes, in: 1...1440)
                            .monospacedDigit()
                            .font(.system(size: 12.5, weight: .medium))
                    }

                    HStack(spacing: 6) {
                        ForEach([5, 10, 15, 25, 45, 60], id: \.self) { mins in
                            Button("\(mins)m") {
                                durationMinutes = mins
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)

                    DatePicker(
                        "Time",
                        selection: $scheduledDate,
                        displayedComponents: [.hourAndMinute]
                    )
                    .font(.system(size: 12))
                }
            }

            HStack(spacing: 8) {
                Text("Accent")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                Spacer()
                ForEach(AccentPreset.allCases) { preset in
                    let dotColor = SpacedTheme.accent(preset, scheme: scheme)
                    Button {
                        selectedAccent = preset
                    } label: {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedAccent == preset ? 2 : 0)
                            )
                            .scaleEffect(selectedAccent == preset ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .help(preset.label)
                }
            }

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 292)
        .preferredColorScheme(scheme)
    }

    private func saveChanges() {
        switch mode {
        case .duration:
            onSave(title, durationMinutes * 60, nil, selectedAccent)
        case .calendar:
            let safeDate = max(Date().addingTimeInterval(15), scheduledDate)
            onSave(title, nil, safeDate, selectedAccent)
        }
    }
}

private struct QuickAdjustPill: View {
    let label: String
    var glassOpacity: Double = 0.78
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SpacedTheme.inkSecondary(for: colorScheme))
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(
                            isHovered
                                ? SpacedTheme.cardSurface(for: colorScheme, glassOpacity: glassOpacity)
                                : SpacedTheme.chipSurface(for: colorScheme, glassOpacity: glassOpacity)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(SpacedTheme.hairlineBorder(for: colorScheme, glassOpacity: glassOpacity), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
    }
}
