import AppKit
import UserNotifications

/// The notification-authorization grant, as Settings needs to talk about it.
///
/// Mirrors `MicrophonePermission` deliberately: same shape, same reasoning —
/// there is no way to re-prompt after a denial, so the only recovery path is a
/// deep link to the pane where the user can flip it back on themselves.
enum NotificationPermission {

    enum Status: Equatable {
        case granted
        case denied
        /// Never asked. Wikily prompts the first time the user turns on
        /// meeting reminders or connects a calendar, not at launch — asking
        /// before there is anything to notify about is how permission prompts
        /// train people to reflexively decline.
        case notDetermined

        var isUsable: Bool { self == .granted }
    }

    static func status() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        // Explicit `return` rather than an implicit trailing switch: with a
        // `let` ahead of it, the switch's branches have no contextual type to
        // resolve `.granted`/`.denied`/etc. against without one.
        return switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Trigger the system prompt. Only meaningful while `.notDetermined` —
    /// once denied, macOS never prompts again and the user has to go to the
    /// pane.
    @discardableResult
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Deep link to System Settings › Notifications › Wikily.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
