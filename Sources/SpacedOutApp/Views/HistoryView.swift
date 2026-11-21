import SpacedOutCore
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case completed = "Completed"
    case dismissed = "Dismissed"

    var id: String { rawValue }
}

struct HistoryView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var searchQuery = ""
    @State private var filter: HistoryFilter = .all
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

    private var groupedByDay: [(dayTitle: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.finishedAt)
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

        VStack(spacing: 16) {
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

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                    TextField("Search past reminders…", text: $searchQuery)
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
                .help("Clear all history")
            }

            if groupedByDay.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    BrandLogoMark(size: 36, color: SpacedTheme.inkMuted(for: scheme))
                    Text(coordinator.engine.history.isEmpty ? "No completed tasks yet" : "No matching history")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))
                    Text("Finished and dismissed reminders will appear here with quick re-run controls.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                }
                Spacer()
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
            "Clear all task history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                coordinator.engine.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all past reminder logs and cannot be undone.")
        }
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
