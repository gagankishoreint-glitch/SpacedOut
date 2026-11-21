import AppKit
import SpacedOutCore
import SwiftUI

final class FloatingWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWidgetController: NSObject, NSWindowDelegate {
    private let coordinator: AppCoordinator
    private let panel: FloatingWidgetPanel
    private var hostingView: NSHostingView<AnyView>
    private var screenObserver: NSObjectProtocol?
    private var isProgrammaticMove = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator

        let initialWidth = CGFloat(coordinator.engine.settings.widgetScale.width)
        let panel = FloatingWidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 320),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = coordinator.engine.settings.alwaysOnTop ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow

        let root = AnyView(
            FloatingWidgetView(isMenuBarPopover: false)
                .environment(coordinator)
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        super.init()
        panel.delegate = self

        applySettings(coordinator.engine.settings)
        restorePositionOrDefault()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clampInsideVisibleScreen()
            }
        }
    }

    func show(focusInput: Bool) {
        clampInsideVisibleScreen()
        panel.orderFrontRegardless()
        if focusInput {
            panel.makeKey()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func applySettings(_ settings: AppSettings) {
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.alphaValue = CGFloat(settings.widgetOpacity)
        panel.appearance = SpacedTheme.nsAppearance(for: settings.themeMode)
        DispatchQueue.main.async { [weak self] in
            self?.clampInsideVisibleScreen()
        }
    }

    func resetToDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 28,
            y: visible.maxY - size.height - 28
        )
        setFrameOriginProgrammatically(origin)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        let origin = panel.frame.origin
        coordinator.engine.updateSettings {
            $0.widgetOrigin = SavedPoint(x: Double(origin.x), y: Double(origin.y))
        }
    }

    private func restorePositionOrDefault() {
        if let saved = coordinator.engine.settings.widgetOrigin {
            let point = NSPoint(x: saved.x, y: saved.y)
            setFrameOriginProgrammatically(point)
            clampInsideVisibleScreen()
        } else {
            resetToDefaultPosition()
        }
    }

    private func clampInsideVisibleScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let currentFrame = panel.frame
        let matchingScreen = screens.first { $0.visibleFrame.intersects(currentFrame) }
            ?? NSScreen.main
            ?? screens[0]

        let visible = matchingScreen.visibleFrame
        let margin: CGFloat = 12

        let maxX = max(visible.minX + margin, visible.maxX - currentFrame.width - margin)
        let maxY = max(visible.minY + margin, visible.maxY - currentFrame.height - margin)

        let clampedX = min(max(currentFrame.origin.x, visible.minX + margin), maxX)
        let clampedY = min(max(currentFrame.origin.y, visible.minY + margin), maxY)

        if abs(clampedX - currentFrame.origin.x) > 0.5 || abs(clampedY - currentFrame.origin.y) > 0.5 {
            setFrameOriginProgrammatically(NSPoint(x: clampedX, y: clampedY))
        }
    }

    private func setFrameOriginProgrammatically(_ origin: NSPoint) {
        isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        isProgrammaticMove = false
    }
}
