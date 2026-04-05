import AppKit
import Foundation
import OSLog
import UserNotifications

// MARK: - Notification Constants

/// Compile-time string constants for notification identifiers.
/// Marked `nonisolated` so `nonisolated` delegate methods
/// can reference them without isolation errors.
nonisolated enum NotificationConstants {
    /// Notification category for meetings with a joinable link.
    static let meetingWithLinkCategory = "MEETING_WITH_LINK"

    /// Action identifier for the "Join" button on meeting notifications.
    static let joinActionIdentifier = "JOIN_MEETING"

    /// Key for storing the meeting link URL in the notification's userInfo.
    static let meetingLinkUserInfoKey = "meetingLink"

    /// Key for storing the event ID in the notification's userInfo.
    static let eventIdUserInfoKey = "eventId"

    /// Prefix prepended to event IDs to form notification request identifiers.
    static let notificationIdPrefix = "meeting-"
}

// MARK: - NotificationManager

/// Delivers macOS Notification Center alerts as a lighter alternative to the
/// full-screen overlay. Handles permission requests, notification delivery,
/// and the "Join" action when the user taps the notification.
final class NotificationManager: NSObject, NotificationManaging {
    private let logger = Logger(category: "NotificationManager")

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if granted {
                logger.info("Notification permission granted")
            } else {
                logger.info("Notification permission denied by user")
            }
            return granted
        } catch {
            logger.error("Notification permission request failed: \(error.localizedDescription)")
            return false
        }
    }

    func sendMeetingNotification(for event: Event, primaryLink: URL?) async {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Meeting"
        content.body = "\(event.title) — \(Self.timeFormatter.string(from: event.startDate))"
        content.sound = .default

        var userInfo: [String: String] = [NotificationConstants.eventIdUserInfoKey: event.id]

        if let link = primaryLink {
            content.categoryIdentifier = NotificationConstants.meetingWithLinkCategory
            userInfo[NotificationConstants.meetingLinkUserInfoKey] = link.absoluteString
        }

        content.userInfo = userInfo

        let identifier = "\(NotificationConstants.notificationIdPrefix)\(event.id)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil,
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Delivered notification for event \(event.id)")
            AppDiagnostics.record(component: "NotificationManager", phase: "deliver") {
                [
                    "eventId": PrivacyUtils.redactedEventId(event.id),
                    "hasLink": "\(primaryLink != nil)",
                ]
            }
        } catch {
            logger.error(
                "Failed to deliver notification for event \(event.id): \(error.localizedDescription)",
            )
            AppDiagnostics.record(
                component: "NotificationManager",
                phase: "deliver",
                outcome: .failure,
            ) {
                [
                    "eventId": PrivacyUtils.redactedEventId(event.id),
                    "error": PrivacyUtils.redactedError(error),
                ]
            }
        }
    }

    func registerCategories() {
        // UNUserNotificationCenter.current() crashes (NSInternalInconsistencyException)
        // when there is no bundle proxy — e.g., in SPM test runners or CLI tools.
        // Bundle.main.bundleIdentifier alone is insufficient: the xctest runner has an
        // identifier but no valid proxy. Check the URL scheme instead — real .app bundles
        // have a file URL ending in .app.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            logger.debug("Skipping notification registration — not running in an app bundle")
            return
        }

        let joinAction = UNNotificationAction(
            identifier: NotificationConstants.joinActionIdentifier,
            title: "Join",
            options: [.foreground],
        )
        let category = UNNotificationCategory(
            identifier: NotificationConstants.meetingWithLinkCategory,
            actions: [joinAction],
            intentIdentifiers: [],
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        logger.debug("Registered notification categories and delegate")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let userInfo = response.notification.request.content.userInfo

        if response.actionIdentifier == NotificationConstants.joinActionIdentifier,
           let linkString = userInfo[NotificationConstants.meetingLinkUserInfoKey] as? String,
           let url = URL(string: linkString)
        {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }

        completionHandler()
    }

    /// Show notifications even when the app is in the foreground so that
    /// notification-mode calendars still surface alerts while the user
    /// works inside Unmissable's preferences or menu bar.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }
}
