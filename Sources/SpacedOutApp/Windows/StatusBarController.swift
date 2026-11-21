import AppKit
import SpacedOutCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let coordinator: AppCoordinator
    private var statusItem: NSStatusItem?
    private var popoverPanel: FloatingWidgetPanel?
    private var outsideClickMonitor: Any?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                createStatusItem()
            }
            refreshStatusTitle()
        } else {
            closePopover()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    func applySettings(_ settings: AppSettings) {
        popoverPanel?.appearance = SpacedTheme.nsAppearance(for: settings.themeMode)
        popoverPanel?.alphaValue = CGFloat(settings.widgetOpacity)
        refreshStatusTitle()
    }

    func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }

        let now = Date()
        let safePrefix = coordinator.engine.settings.presentationSafeMode ? "● " : ""

        if let triggered = coordinator.engine.triggeredQueue.first {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "SpacedOut Alert")
            button.imagePosition = .imageLeading
            button.title = " \(safePrefix)\(triggered.formattedRemaining(at: now))"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        } else if let next = coordinator.engine.earliestActiveReminder {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "SpacedOut Active")
            button.imagePosition = .imageLeading
            button.title = " \(safePrefix)\(next.formattedRemaining(at: now))"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            let symbolName = coordinator.engine.settings.presentationSafeMode ? "eye.slash.circle" : "timer"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SpacedOut")
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    func togglePopover() {
        if let panel = popoverPanel, panel.isVisible {
            closePopover()
        } else {
            openPopover()
        }
    }

    func openPopover() {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            coordinator.showFloatingWidget(focusInput: true)
            return
        }

        let panel = ensurePopoverPanel()
        let buttonRect = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size

        var x = buttonRect.midX - panelSize.width / 2
        let y = buttonRect.minY - panelSize.height - 6

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - panelSize.width - 8)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panel.makeKey()
        coordinator.isMenuBarPopoverVisible = true
        coordinator.focusInputTrigger = UUID()

        installOutsideClickMonitor()
    }

    func closePopover() {
        popoverPanel?.orderOut(nil)
        coordinator.isMenuBarPopoverVisible = false
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            closePopover()
            showContextMenu()
            return
        }

        switch coordinator.engine.settings.displayMode {
        case .menuBarOnly:
            togglePopover()
        case .widgetAndMenuBar, .widgetOnly:
            coordinator.toggleFloatingWidget(focusInput: true)
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let presetsHeader = NSMenuItem(title: "Quick Start", action: nil, keyEquivalent: "")
        presetsHeader.isEnabled = false
        menu.addItem(presetsHeader)

        for mins in coordinator.engine.settings.quickPresetsMinutes {
            let item = NSMenuItem(
                title: "Start \(mins)m Reminder",
                action: #selector(handleQuickPresetMenu(_:)),
                keyEquivalent: ""
            )
            item.tag = mins
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if coordinator.engine.settings.displayMode != .menuBarOnly {
            let toggleTitle = coordinator.isWidgetVisible ? "Hide Floating Widget" : "Show Floating Widget"
            let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleWidget), keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
        } else {
            let popItem = NSMenuItem(title: "Open Quick Panel", action: #selector(handleOpenPopover), keyEquivalent: "")
            popItem.target = self
            menu.addItem(popItem)
        }

        let safeItem = NSMenuItem(
            title: "Presentation Safe Mode",
            action: #selector(handleToggleSafeMode),
            keyEquivalent: ""
        )
        safeItem.state = coordinator.engine.settings.presentationSafeMode ? .on : .off
        safeItem.target = self
        menu.addItem(safeItem)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "Task History…", action: #selector(handleOpenHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SpacedOut", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func ensurePopoverPanel() -> FloatingWidgetPanel {
        if let popoverPanel {
            return popoverPanel
        }

        let width = CGFloat(coordinator.engine.settings.widgetScale.width)
        let panel = FloatingWidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 320),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = SpacedTheme.nsAppearance(for: coordinator.engine.settings.themeMode)

        let hosting = NSHostingView(
            rootView: FloatingWidgetView(isMenuBarPopover: true)
                .environment(coordinator)
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        popoverPanel = panel
        return panel
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    @objc private func handleQuickPresetMenu(_ sender: NSMenuItem) {
        coordinator.createPresetReminder(minutes: sender.tag, title: "")
    }

    @objc private func handleToggleWidget() {
        coordinator.toggleFloatingWidget(focusInput: true)
    }

    @objc private func handleOpenPopover() {
        openPopover()
    }

    @objc private func handleToggleSafeMode() {
        coordinator.togglePresentationSafeMode()
    }

    @objc private func handleOpenHistory() {
        coordinator.openHistoryWindow()
    }

    @objc private func handleOpenSettings() {
        coordinator.openSettingsWindow()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
