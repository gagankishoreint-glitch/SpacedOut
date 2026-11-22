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

    private var accent: Color { SpacedTheme.accent(.mint, scheme: colorScheme) }
    private var ink: Color { SpacedTheme.inkPrimary(for: colorScheme) }
    private var secondary: Color { SpacedTheme.inkSecondary(for: colorScheme) }
    private var progress: Double { Double(minutes) / Double(maxDialMinutes) }

    var body: some View {
        ZStack {
            tickMarks
            trackRing
            progressRing
            thumb
            centerButton
        }
        .frame(width: dialDiameter + 26, height: dialDiameter + 26)
        .contentShape(Circle())
        .gesture(dragGesture)
    }

    // MARK: - Subviews

    private var tickMarks: some View {
        let secondary = self.secondary
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius: CGFloat = min(size.width, size.height) / 2 - 4

            for step in 0..<60 {
                let isMajor = step % 5 == 0
                let tickLength: CGFloat = isMajor ? 7 : 3.5
                let angle = CGFloat(-Double.pi / 2 + (Double(step) / 60.0) * 2.0 * Double.pi)

                var path = Path()
                path.move(to: Self.point(on: center, radius: outerRadius - tickLength, angle: angle))
                path.addLine(to: Self.point(on: center, radius: outerRadius, angle: angle))

                let color: Color = secondary.opacity(isMajor ? 0.45 : 0.20)
                let style = StrokeStyle(lineWidth: isMajor ? 1.5 : 1.0, lineCap: .round)
                context.stroke(path, with: .color(color), style: style)
            }
        }
        .frame(width: dialDiameter + 22, height: dialDiameter + 22)
        .allowsHitTesting(false)
    }

    private var trackRing: some View {
        Circle()
            .stroke(
                SpacedTheme.subtleSeparator(for: colorScheme),
                style: StrokeStyle(lineWidth: 10, lineCap: .round)
            )
            .frame(width: dialDiameter, height: dialDiameter)
    }

    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: dialDiameter, height: dialDiameter)
            .animation(.easeOut(duration: 0.08), value: minutes)
    }

    private var thumb: some View {
        let angle = CGFloat(-Double.pi / 2 + progress * 2.0 * Double.pi)
        let offset = Self.point(on: .zero, radius: dialDiameter / 2, angle: angle)

        return Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
            .overlay(Circle().stroke(accent, lineWidth: 2.5))
            .offset(x: offset.x, y: offset.y)
            .allowsHitTesting(false)
    }

    private var centerButton: some View {
        Button(action: onStartTapped) {
            centerLabel
                .frame(width: 96, height: 96)
                .background(Circle().fill(centerFill))
                .overlay(
                    Circle().stroke(SpacedTheme.hairlineBorder(for: colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            isHoveringCenter = hovering
        }
    }

    private var centerLabel: some View {
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
    }

    private var centerFill: Color {
        guard isHoveringCenter else { return SpacedTheme.cardSurface(for: colorScheme) }
        return accent.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let side: CGFloat = dialDiameter + 26
                let dx: CGFloat = value.location.x - side / 2
                let dy: CGFloat = value.location.y - side / 2
                // ignore taps inside the 96pt center start button
                guard hypot(dx, dy) > 48 else { return }

                var angle = Double(atan2(dy, dx)) + Double.pi / 2
                if angle < 0 { angle += 2 * Double.pi }
                let fraction = angle / (2 * Double.pi)
                let raw = Int((fraction * Double(maxDialMinutes)).rounded())
                let nextMinutes = max(1, min(maxDialMinutes, raw))
                if nextMinutes != minutes {
                    minutes = nextMinutes
                    onMinuteTick()
                }
            }
    }

    // MARK: - Geometry

    private static func point(on center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}
