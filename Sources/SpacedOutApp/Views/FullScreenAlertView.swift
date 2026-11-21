import SpacedOutCore
import SwiftUI

struct FullScreenAlertView: View {
    let isPrimaryDisplay: Bool

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseExpanded = false

    private var effectiveColorScheme: ColorScheme {
        switch coordinator.engine.settings.themeMode {
        case .system: return systemColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let scheme = effectiveColorScheme
        let accent = SpacedTheme.accent(.mint, scheme: scheme)
        let inkPrimary = SpacedTheme.inkPrimary(for: scheme)
        let inkSecondary = SpacedTheme.inkSecondary(for: scheme)
        let inkMuted = SpacedTheme.inkMuted(for: scheme)

        ZStack {
            VisualEffectView(
                material: .fullScreenUI,
                blendingMode: .behindWindow,
                state: .active
            )

            (scheme == .dark
                ? Color(red: 0.03, green: 0.08, blue: 0.06).opacity(0.68)
                : Color(red: 0.88, green: 0.98, blue: 0.92).opacity(0.62))
                .ignoresSafeArea()

            if let item = coordinator.currentAlertItem {
                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.20), lineWidth: 2)
                            .frame(width: 112, height: 112)
                            .scaleEffect(pulseExpanded ? 1.18 : 0.94)
                            .opacity(pulseExpanded ? 0.15 : 0.65)

                        Circle()
                            .fill(accent.opacity(scheme == .dark ? 0.18 : 0.14))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle().stroke(accent.opacity(0.35), lineWidth: 1.5)
                            )

                        BrandLogoMark(size: 40, color: accent)
                    }
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            pulseExpanded = true
                        }
                    }

                    HStack(spacing: 8) {
                        Text(coordinator.testPreviewReminder != nil ? "ALERT PREVIEW" : "TIME'S UP")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(accent)

                        if coordinator.activeAlertQueueCount > 1 {
                            Text("1 of \(coordinator.activeAlertQueueCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(inkSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SpacedTheme.chipSurface(for: scheme)))
                        }
                    }

                    Text(item.displayTitle)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(inkPrimary)
                        .frame(maxWidth: 680)

                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        let elapsedOverdue = item.formattedRemaining(at: context.date)
                        HStack(spacing: 10) {
                            Text("Planned \(ReminderItem.formatDuration(item.durationSeconds))")
                            Text("·")
                            Text(elapsedOverdue == "00:00" ? "Due now" : "\(elapsedOverdue) overdue")
                                .foregroundStyle(SpacedTheme.overdueCoral(for: scheme))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(inkSecondary)
                    }

                    VStack(spacing: 14) {
                        Button {
                            coordinator.resolveAlert(id: item.id, action: .complete)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Complete")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 34)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(accent))
                            .shadow(color: accent.opacity(0.28), radius: 12, y: 4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())

                        HStack(spacing: 10) {
                            SnoozePillButton(title: "+1m", shortcutHint: "1", scheme: scheme) {
                                coordinator.resolveAlert(id: item.id, action: .snooze(seconds: 60))
                            }
                            SnoozePillButton(title: "+5m", shortcutHint: "2", scheme: scheme) {
                                coordinator.resolveAlert(id: item.id, action: .snooze(seconds: 300))
                            }
                            SnoozePillButton(title: "+10m", shortcutHint: "3", scheme: scheme) {
                                coordinator.resolveAlert(id: item.id, action: .snooze(seconds: 600))
                            }
                            SnoozePillButton(title: "+15m", shortcutHint: "4", scheme: scheme) {
                                coordinator.resolveAlert(id: item.id, action: .snooze(seconds: 900))
                            }
                        }

                        Button {
                            coordinator.resolveAlert(id: item.id, action: .dismiss)
                        } label: {
                            Text("Dismiss without completing")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(inkMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                    }
                    .padding(.top, 6)

                    Spacer()

                    if isPrimaryDisplay {
                        Text("Space / Return to Complete  ·  Keys 1–4 to Snooze  ·  Esc to Dismiss")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(inkMuted)
                            .padding(.bottom, 26)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .preferredColorScheme(SpacedTheme.colorScheme(for: coordinator.engine.settings.themeMode))
    }
}

private struct SnoozePillButton: View {
    let title: String
    let shortcutHint: String
    let scheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Snooze \(title)")
                    .font(.system(size: 13.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(SpacedTheme.inkPrimary(for: scheme))

                Text(shortcutHint)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SpacedTheme.inkMuted(for: scheme))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SpacedTheme.subtleSeparator(for: scheme))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(
                        isHovered
                            ? (scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.84))
                            : SpacedTheme.cardSurface(for: scheme)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(SpacedTheme.hairlineBorder(for: scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
    }
}
