import SpacedOutCore
import SwiftUI

struct ReminderRowView: View {
    let item: ReminderItem
    var onTogglePause: () -> Void
    var onAdjust: (Int) -> Void
    var onRename: (String) -> Void
    var onComplete: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
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
                    // Progress ring button (click toggles pause/resume)
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

                    // Title + target wall-clock subtitle
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
                                draftTitle = item.title
                                isEditingTitle = true
                                titleFieldFocused = true
                            }
                            .help("Click to rename")
                        }

                        HStack(spacing: 6) {
                            if isPaused {
                                Text("Paused")
                                    .foregroundStyle(SpacedTheme.urgencyAmber(for: colorScheme))
                            } else {
                                Text("Ends \(item.targetDate, style: .time)")
                                    .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                            }

                            if item.externalReminderID != nil {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(SpacedTheme.inkMuted(for: colorScheme))
                                    .help("Synced to Apple Reminders")
                            }
                        }
                        .font(.system(size: 10.5))
                    }

                    Spacer(minLength: 6)

                    // Crisp tabular countdown
                    Text(item.formattedRemaining(at: now))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            isUrgent
                                ? SpacedTheme.overdueCoral(for: colorScheme)
                                : SpacedTheme.inkPrimary(for: colorScheme)
                        )
                }

                // Hover quick edit controls (DeskMinder fix: edit/extend/complete without deleting!)
                if isHovered {
                    HStack(spacing: 5) {
                        QuickAdjustPill(label: "-1m") { onAdjust(-60) }
                        QuickAdjustPill(label: "+1m") { onAdjust(60) }
                        QuickAdjustPill(label: "+5m") { onAdjust(300) }

                        Spacer()

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
                                .background(Circle().fill(SpacedTheme.chipSurface(for: colorScheme)))
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
                    .fill(SpacedTheme.cardSurface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isUrgent
                            ? SpacedTheme.overdueCoral(for: colorScheme).opacity(0.45)
                            : SpacedTheme.hairlineBorder(for: colorScheme),
                        lineWidth: 1
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
    }

    private func commitRename() {
        isEditingTitle = false
        onRename(draftTitle)
    }

    private func cancelRename() {
        isEditingTitle = false
        draftTitle = item.title
    }
}

private struct QuickAdjustPill: View {
    let label: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(SpacedTheme.inkSecondary(for: colorScheme))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(SpacedTheme.chipSurface(for: colorScheme))
                )
                .overlay(
                    Capsule()
                        .stroke(SpacedTheme.hairlineBorder(for: colorScheme), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
