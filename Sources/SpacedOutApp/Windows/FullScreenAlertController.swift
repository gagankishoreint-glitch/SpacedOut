import AppKit
import SpacedOutCore
import SwiftUI

final class FullScreenAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FullScreenAlertController {
    private let coordinator: AppCoordinator
    private var windows: [FullScreenAlertPanel] = []
    private var closingWindows: [FullScreenAlertPanel] = []
    private var localKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func showOrUpdate() {
        guard coordinator.currentAlertItem != nil else {
            dismissAll()
            return
        }

        if windows.isEmpty {
            buildWindowsForAllScreens()
            installKeyMonitor()
            observeScreenChanges()
        }
    }

    func dismissAll() {
        removeKeyMonitor()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        guard !windows.isEmpty else { return }
        closingWindows.append(contentsOf: windows)
        windows.removeAll()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            for window in closingWindows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                for window in self.closingWindows {
                    window.orderOut(nil)
                    window.close()
                }
                self.closingWindows.removeAll()
            }
        })
    }

    private func buildWindowsForAllScreens() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let appearance = SpacedTheme.nsAppearance(for: coordinator.engine.settings.themeMode)
        var created: [FullScreenAlertPanel] = []

        for (index, screen) in screens.enumerated() {
            let panel = FullScreenAlertPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.appearance = appearance
            panel.alphaValue = 0

            let view = FullScreenAlertView(isPrimaryDisplay: index == 0)
                .environment(coordinator)
            panel.contentView = NSHostingView(rootView: view)
            panel.orderFrontRegardless()
            if index == 0 {
                panel.makeKey()
            }
            created.append(panel)
        }

        windows = created

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in created {
                window.animator().alphaValue = 1
            }
        }
    }

    private func observeScreenChanges() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.windows.isEmpty else { return }
                for window in self.windows {
                    window.orderOut(nil)
                    window.close()
                }
                self.windows.removeAll()
                self.buildWindowsForAllScreens()
            }
        }
    }

    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let current = self.coordinator.currentAlertItem else {
                return event
            }

            switch event.keyCode {
            case 36, 76, 49: // return / enter / space
                self.coordinator.resolveAlert(id: current.id, action: .complete)
                return nil
            case 53: // esc
                self.coordinator.resolveAlert(id: current.id, action: .dismiss)
                return nil
            case 18:
                self.coordinator.resolveAlert(id: current.id, action: .snooze(seconds: 60))
                return nil
            case 19:
                self.coordinator.resolveAlert(id: current.id, action: .snooze(seconds: 300))
                return nil
            case 20:
                self.coordinator.resolveAlert(id: current.id, action: .snooze(seconds: 600))
                return nil
            case 21:
                self.coordinator.resolveAlert(id: current.id, action: .snooze(seconds: 900))
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
