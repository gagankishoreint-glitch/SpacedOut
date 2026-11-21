import Foundation
import SpacedOutCore
import UserNotifications

@MainActor
final class NotificationService {
    private static let categoryIdentifier = "SPACEDOUT_REMINDER"
    private static let completeActionID = "SPACEDOUT_COMPLETE"
    private static let snooze5ActionID = "SPACEDOUT_SNOOZE_5M"

    var onAction: (@MainActor @Sendable (UUID, String) -> Void)?

    private var delegateProxy: DelegateProxy?

    var isSupportedInCurrentBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func configure() {
        guard isSupportedInCurrentBundle else { return }
        let center = UNUserNotificationCenter.current()
        let proxy = DelegateProxy { [weak self] reminderID, actionID in
            self?.onAction?(reminderID, actionID)
        }
        self.delegateProxy = proxy
        center.delegate = proxy

        let completeAction = UNNotificationAction(
            identifier: Self.completeActionID,
            title: "Complete",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snooze5ActionID,
            title: "Snooze +5m",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestPermissionIfNeeded() async {
        guard isSupportedInCurrentBundle else { return }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func postDueBanner(for reminder: ReminderItem) {
        guard isSupportedInCurrentBundle else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "SpacedOut"
        content.subtitle = reminder.displayTitle
        content.body = "Timer finished (\(ReminderItem.formatDuration(reminder.durationSeconds)))."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func postPreAlertBanner(for reminder: ReminderItem, secondsRemaining: Int) {
        guard isSupportedInCurrentBundle else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Heads up · \(secondsRemaining)s left"
        content.body = reminder.displayTitle
        content.categoryIdentifier = Self.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: "prealert-\(reminder.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func clearDelivered(for reminderID: UUID) {
        guard isSupportedInCurrentBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [
            reminderID.uuidString,
            "prealert-\(reminderID.uuidString)"
        ])
    }

    static func isCompleteAction(_ actionID: String) -> Bool { actionID == completeActionID }
    static func isSnoozeAction(_ actionID: String) -> Bool { actionID == snooze5ActionID }

    private final class DelegateProxy: NSObject, UNUserNotificationCenterDelegate, Sendable {
        private let handler: @MainActor @Sendable (UUID, String) -> Void

        init(handler: @escaping @MainActor @Sendable (UUID, String) -> Void) {
            self.handler = handler
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let rawID = response.notification.request.identifier
                .replacingOccurrences(of: "prealert-", with: "")
            guard let uuid = UUID(uuidString: rawID) else { return }
            let actionID = response.actionIdentifier
            let callback = handler
            await MainActor.run {
                callback(uuid, actionID)
            }
        }
    }
}
