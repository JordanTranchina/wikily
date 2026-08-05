import AppKit
import UserNotifications

/// Handles the "Join & Open Wikily" action — and the default tap, which does
/// the same thing — on a meeting reminder notification.
///
/// A separate object rather than a closure owned by `MeetingNotificationScheduler`
/// because `UNUserNotificationCenterDelegate` is how AppKit hands back *any*
/// notification interaction, and the center's `delegate` property has to be
/// set once at launch independent of whichever `MeetingNotificationScheduler`
/// instance happens to be alive when the tap arrives.
@MainActor
final class MeetingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let openJoinURL: (URL) -> Void
    private let showOverlay: () -> Void

    /// - Parameters:
    ///   - openJoinURL: opens the meeting link — `NSWorkspace.shared.open`
    ///     in production, a recording closure in tests.
    ///   - showOverlay: brings Wikily's HUD forward, so "join and use Wikily"
    ///     — the point of the whole feature — is one tap, not two.
    init(openJoinURL: @escaping (URL) -> Void, showOverlay: @escaping () -> Void) {
        self.openJoinURL = openJoinURL
        self.showOverlay = showOverlay
    }

    /// Show the banner even while Wikily is frontmost. The whole point is
    /// catching a user mid-call-prep, not just when the app is backgrounded —
    /// the default behaviour of suppressing a notification while its owning
    /// app is active would silently drop exactly the reminders this feature
    /// exists to deliver.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler()
            return
        }

        let userInfo = response.notification.request.content.userInfo
        let joinURLString = userInfo[MeetingNotificationScheduler.joinURLUserInfoKey] as? String

        Task { @MainActor in
            self.showOverlay()
            if let joinURLString, !joinURLString.isEmpty, let url = URL(string: joinURLString) {
                self.openJoinURL(url)
            }
            completionHandler()
        }
    }
}
