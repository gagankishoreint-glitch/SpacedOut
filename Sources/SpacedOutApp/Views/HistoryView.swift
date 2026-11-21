import SpacedOutCore
import SwiftUI

enum HistoryWindowTab: String, CaseIterable, Identifiable {
    case taskHistory = "Task History"
    case activityLog = "Activity Log"

    var id: String { rawValue }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case completed = "Completed"
    case dismissed = "Dismissed"

    var id: String { rawValue }
}

struct HistoryView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var selectedTab: HistoryWindowTab = .taskHistory
    @State private var searchQuery = ""
    @State private var filter: HistoryFilter = .all
    @State private var logCategory: ActivityLogCategory = .all
    @State private var showClearConfirmation = false

    private var scheme: ColorScheme {
        switch coordinator.engine.settings.themeMode {
        case .system: return systemColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var filteredEntries: [HistoryEntry] {
        coordinator.engine.history.filter { entry in
            switch filter {
            case .all: break
            case .completed: guard entry.outcome == .completed else { return false }
            case .dismissed: guard entry.outcome == .dismissed else { return false }
            }

            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            return entry.displayTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredLogEntries: [ActivityLogEntry] {
        coordinator.engine.activityLog.filter { entry in
            if logCategory != .all && entry.kind.category != logCategory {
                return false
            }
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            return entry.reminderTitle.localizedCaseInsensitiveContains(q)
                || entry.details.localizedCaseInsensitiveContains(q)
                || entry.kind.label.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedByDay: [(dayTitle: String, entries: [HistoryEntry])] {
        groupDates(filteredEntries, dateKeyPath: \.finishedAt)
    }

    private var groupedLogByDay: [(dayTitle: String, entries: [ActivityLogEntry])] {
        groupDates(filteredLogEntries, dateKeyPath: \.timestamp)
    }

    private func groupDates<T>(_ items: [T], dateKeyPath: KeyPath<T, Date>) -> [(dayTitle: String, entries: [T])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item[keyPath: dateKeyPath])
        }
        let sortedDays = grouped.keys.sorted(by: >)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return sortedDays.map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "Today"
            } else if calendar.isDateInYesterday(day) {
                title = "Yesterday"
            } else {
                title = formatter.string(from: day)
            }
            return (title, grouped[day] ?? [])
        }
    }

    var body: some View {
        let stats = coordinator.engine.dailyStats()
        let accent = SpacedTheme.accent(.mint, scheme: scheme)

        VStack(spacing: 14) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("Task History").tag(HistoryWindowTab.taskHistory)
                    Text("Activity Log (\(coordinator.engine.activityLog.count))").tag(HistoryWindowTab.activityLog)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 290)

                Spacer()
            }

            if selectedTab == .taskHistory {
                HStack(spacing: 10) {
                    StatTile(
                        title: "Completed Today",
                        value: "\(stats.completedCount)",
                        icon: "checkmark.circle.fill",
                        accent: accent,
                        scheme: scheme
                    )
                    StatTile(
                        title: "Focus Minutes",
                        value: "\(stats.totalFocusMinutes)m",
                        icon: "clock.fill",
                        accent: SpacedTheme.accent(.sky, scheme: scheme),
                        scheme: scheme
                    )
                    StatTile(
                        title: "On-Time Rate",
                        value: "\(stats.onTimePercentage)%",
                        icon: "sparkles",
                        accent: SpacedTheme.accent(.amber, scheme: scheme),
                        scheme: scheme
                    )
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                    TextField(
                        selectedTab == .taskHistory ? "Search past reminders…" : "Search activity log…",
                        text: $searchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SpacedTheme.cardSurface(for: scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 0.8)
                )

                if selectedTab == .taskHistory {
                    Picker("", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)

                    Button {
                        coordinator.exportICS()
                    } label: {
                        Label("Export .ics", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.history.isEmpty && coordinator.engine.activeOrPausedReminders.isEmpty)

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.history.isEmpty)
                    .help("Clear all task history")
                } else {
                    Picker("", selection: $logCategory) {
                        ForEach(ActivityLogCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    Button {
                        coordinator.exportActivityLog()
                    } label: {
                        Label("Export Log", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.activityLog.isEmpty)

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.activityLog.isEmpty)
                    .help("Clear activity log")
                }
            }

            if selectedTab == .taskHistory {
                if groupedByDay.isEmpty {
                    emptyPlaceholder(
                        title: coordinator.engine.history.isEmpty ? "No completed tasks yet" : "No matching history",
                        subtitle: "Finished and dismissed reminders will appear here with quick re-run controls."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groupedByDay, id: \.dayTitle) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.dayTitle.uppercased())
                                        .font(.system(size: 10.5, weight: .bold))
                                        .tracking(0.9)
                                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                                        .padding(.horizontal, 4)

                                    ForEach(section.entries) { entry in
                                        HistoryEntryRow(
                                            entry: entry,
                                            scheme: scheme,
                                            onRerun: {
                                                coordinator.engine.rerunHistoryEntry(entry)
                                                coordinator.showFloatingWidget(focusInput: false)
                                            },
                                            onDelete: {
                                                coordinator.engine.deleteHistoryEntry(id: entry.id)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
            } else {
                if groupedLogByDay.isEmpty {
                    emptyPlaceholder(
                        title: coordinator.engine.activityLog.isEmpty ? "No activity logged yet" : "No matching log entries",
                        subtitle: "Creates, edits, snoozes, restarts, Apple sync changes, and removals are recorded here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groupedLogByDay, id: \.dayTitle) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.dayTitle.uppercased())
                                        .font(.system(size: 10.5, weight: .bold))
                                        .tracking(0.9)
                                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                                        .padding(.horizontal, 4)

                                    ForEach(section.entries) { entry in
                                        ActivityLogEntryRow(entry: entry, scheme: scheme)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .padding(20)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                SpacedTheme.widgetTintWash(for: scheme).opacity(0.65)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(SpacedTheme.colorScheme(for: coordinator.engine.settings.themeMode))
        .confirmationDialog(
            selectedTab == .taskHistory ? "Clear all task history?" : "Clear entire activity log?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                if selectedTab == .taskHistory {
                    coordinator.engine.clearHistory()
                } else {
                    coordinator.engine.clearActivityLog()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected logs locally and cannot be undone.")
        }
    }

    @ViewBuilder
    private func emptyPlaceholder(title: String, subtitle: String) -> some View {
        Spacer()
        VStack(spacing: 10) {
            BrandLogoMark(size: 36, color: SpacedTheme.inkMuted(for: scheme))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        Spacer()
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpacedTheme.cardSurface(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 0.9)
        )
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let scheme: ColorScheme
    let onRerun: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let isCompleted = entry.outcome == .completed
        let statusColor = isCompleted
            ? SpacedTheme.accent(.mint, scheme: scheme)
            : SpacedTheme.inkMuted(for: scheme)

        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 15))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(ReminderItem.formatDuration(entry.plannedDurationSeconds))
                        .monospacedDigit()

                    Text("·")

                    Text(entry.finishedAt, style: .time)
                        .monospacedDigit()

                    if entry.snoozeCount > 0 {
                        Text("· Snoozed \(entry.snoozeCount)×")
                            .foregroundStyle(SpacedTheme.urgencyAmber(for: scheme))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
            }

            Spacer()

            if isHovered {
                Button(action: onRerun) {
                    Label("Run Again", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SpacedTheme.cardSurface(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 0.8)
        )
        .onHover { isHovered = $0 }
    }
}

private struct ActivityLogEntryRow: View {
    let entry: ActivityLogEntry
    let scheme: ColorScheme

    var body: some View {
        let style = badgeStyle(for: entry.kind)

        HStack(alignment: .center, spacing: 11) {
            Image(systemName: style.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(style.color.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.reminderTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
                        .lineLimit(1)

                    Text(entry.kind.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(style.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(style.color.opacity(0.12)))
                }

                Text(entry.details)
                    .font(.system(size: 11))
                    .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SpacedTheme.cardSurface(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 0.8)
        )
    }

    private func badgeStyle(for kind: ActivityEventKind) -> (icon: String, color: Color) {
        switch kind {
        case .created: return ("plus.circle.fill", SpacedTheme.accent(.mint, scheme: scheme))
        case .edited: return ("pencil.circle.fill", SpacedTheme.accent(.sky, scheme: scheme))
        case .adjusted: return ("slider.horizontal.3", SpacedTheme.accent(.sky, scheme: scheme))
        case .paused: return ("pause.circle.fill", SpacedTheme.urgencyAmber(for: scheme))
        case .resumed: return ("play.circle.fill", SpacedTheme.accent(.mint, scheme: scheme))
        case .snoozed: return ("zzz", SpacedTheme.urgencyAmber(for: scheme))
        case .triggered: return ("bell.badge.fill", SpacedTheme.overdueCoral(for: scheme))
        case .completed: return ("checkmark.circle.fill", SpacedTheme.accent(.mint, scheme: scheme))
        case .dismissed: return ("minus.circle.fill", SpacedTheme.inkMuted(for: scheme))
        case .deleted: return ("trash.circle.fill", SpacedTheme.overdueCoral(for: scheme))
        case .recoveredAfterRestart: return ("arrow.clockwise.circle.fill", SpacedTheme.urgencyAmber(for: scheme))
        case .externalSyncUpdated: return ("arrow.triangle.2.circlepath.circle.fill", SpacedTheme.accent(.sky, scheme: scheme))
        case .externalSyncDeleted: return ("calendar.badge.minus", SpacedTheme.overdueCoral(for: scheme))
        case .watchdogEvent: return ("shield.lefthalf.filled", SpacedTheme.accent(.amber, scheme: scheme))
        }
    }
}
