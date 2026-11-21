import SpacedOutCore
import SwiftUI

struct TactileDialView: View {
    @Binding var minutes: Int
    var onMinuteTick: () -> Void
    var onStartTapped: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringCenter = false

    private let maxDialMinutes = 99
    private let dialDiameter: CGFloat = 152

    var body: some View {
        let accent = SpacedTheme.accent(.mint, scheme: colorScheme)
        let ink = SpacedTheme.inkPrimary(for: colorScheme)
        let secondary = SpacedTheme.inkSecondary(for: colorScheme)
        let progress = Double(minutes) / Double(maxDialMinutes)

        ZStack {
            // Precision tick marks around perimeter
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outerRadius = min(size.width, size.height) / 2 - 4

                for step in 0..<60 {
                    let angle = -Double.pi / 2 + (Double(step) / 60.0) * 2.0 * Double.pi
                    let isMajor = step % 5 == 0
                    let tickLen: CGFloat = isMajor ? 7 : 3.5
                    let innerR = outerRadius - tickLen

                    let p1 = CGPoint(
                        x: center.x + cos(angle) * innerR,
                        y: center.y + sin(angle) * innerR
                    )
                    let p2 = CGPoint(
                        x: center.x + cos(angle) * outerRadius,
                        y: center.y + sin(angle) * outerRadius
                    )

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    let color = isMajor
                        ? secondary.opacity(0.45)
                        : secondary.opacity(0.20)
                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: isMajor ? 1.5 : 1.0, lineCap: .round)
                    )
                }
            }
            .frame(width: dialDiameter + 22, height: dialDiameter + 22)
            .allowsHitTesting(false)

            // Base frosted ring track
            Circle()
                .stroke(
                    SpacedTheme.subtleSeparator(for: colorScheme),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: dialDiameter, height: dialDiameter)

            // Active sweep arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: dialDiameter, height: dialDiameter)
                .animation(.easeOut(duration: 0.08), value: minutes)

            // Interactive knob thumb
            let thumbAngle = -Double.pi / 2 + progress * 2.0 * Double.pi
            let radius = dialDiameter / 2
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
                .overlay(
                    Circle()
                        .stroke(accent, lineWidth: 2.5)
                )
                .offset(
                    x: cos(thumbAngle) * radius,
                    y: sin(thumbAngle) * radius
                )
                .allowsHitTesting(false)

            // Center Start button + readout
            Button(action: onStartTapped) {
                VStack(spacing: 2) {
                    Text("\(minutes)m")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)

                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let target = context.date.addingTimeInterval(TimeInterval(minutes * 60))
                        Text(target, style: .time)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(secondary)
                    }

                    Text(isHoveringCenter ? "Start Timer" : "Click to Start")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                }
                .frame(width: 96, height: 96)
                .background(
                    Circle()
                        .fill(
                            isHoveringCenter
                                ? accent.opacity(colorScheme == .dark ? 0.16 : 0.12)
                                : SpacedTheme.cardSurface(for: colorScheme)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(SpacedTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                isHoveringCenter = hovering
            }
        }
        .frame(width: dialDiameter + 26, height: dialDiameter + 26)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: (dialDiameter + 26) / 2, y: (dialDiameter + 26) / 2)
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    // Ignore drags inside the 96pt center Start button
                    let distance = hypot(dx, dy)
                    guard distance > 48 else { return }

                    var angle = atan2(dy, dx) + Double.pi / 2
                    if angle < 0 { angle += 2 * Double.pi }
                    let fraction = angle / (2 * Double.pi)
                    let nextMinutes = max(1, min(maxDialMinutes, Int((fraction * Double(maxDialMinutes)).rounded())))
                    if nextMinutes != minutes {
                        minutes = nextMinutes
                        onMinuteTick()
                    }
                }
        )
    }
}
