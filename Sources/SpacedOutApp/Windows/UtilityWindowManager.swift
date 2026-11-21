import AppKit
import SpacedOutCore
import SwiftUI

@MainActor
final class UtilityWindowManager {
    private let coordinator: AppCoordinator
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func showHistory() {
        let window = ensureHistoryWindow()
        window.appearance = SpacedTheme.nsAppearance(for: coordinator.engine.settings.themeMode)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        let window = ensureSettingsWindow()
        window.appearance = SpacedTheme.nsAppearance(for: coordinator.engine.settings.themeMode)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applyTheme(_ theme: ThemeMode) {
        let appearance = SpacedTheme.nsAppearance(for: theme)
        historyWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    private func ensureHistoryWindow() -> NSWindow {
        if let historyWindow {
            return historyWindow
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Task History"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        window.contentView = NSHostingView(
            rootView: HistoryView()
                .environment(coordinator)
        )
        historyWindow = window
        return window
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow {
            return settingsWindow
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacedOut Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environment(coordinator)
        )
        settingsWindow = window
        return window
    }
}
