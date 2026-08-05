import Foundation
import OSLog
import UserNotifications

/// The subset of `UNUserNotificationCenter` this file touches, as a protocol.
///
/// Exists for the same reason `LaunchAtLoginControl` wraps `SMAppService`: a
/// test suite scheduling and cancelling reminders shouldn't be asking the real
/// notification center to do either, and shouldn't need notification
/// authorization granted on the test host to verify the scheduling logic.
protocol UNUserNotificationCenterProviding {
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UNUserNotificationCenterProviding {}

/// Turns "a meeting with a join link starts in one minute" into a system
/// notification with a one-tap "Join & Open Wikily" action.
///
/// Runs entirely off `CalendarSyncCoordinator.upcomingEvents` — it has no
/// timer of its own. The coordinator already polls every minute (see its
/// header), so a notification's fire time is computed once per event and
/// handed to `UNUserNotificationCenter`, which keeps counting down
/// independently of whatever the next refresh cycle does.
@MainActor
final class MeetingNotificationScheduler {

    static let categoryIdentifier = "com.wikily.Wikily.meetingReminder"
    static let joinActionIdentifier = "com.wikily.Wikily.joinMeeting"
    static let joinURLUserInfoKey = "joinURL"

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "MeetingNotificationScheduler")

    private let coordinator: CalendarSyncCoordinator
    private let settings: AppSettings
    private let center: any UNUserNotificationCenterProviding
    private let leadTime: TimeInterval
    private let now: @Sendable () -> Date

    /// Identifiers this instance has asked the notification center to
    /// schedule, so a reconcile pass knows what to leave alone versus cancel.
    private var scheduledIdentifiers: Set<String> = []

    init(
        coordinator: CalendarSyncCoordinator = .shared,
        settings: AppSettings = .shared,
        center: any UNUserNotificationCenterProviding = UNUserNotificationCenter.current(),
        leadTime: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.center = center
        self.leadTime = leadTime
        self.now = now
    }

    /// Registers the "Join & Open Wikily" action/category and starts
    /// observing `coordinator.upcomingEvents`. Call once at launch.
    func start() {
        let joinAction = UNNotificationAction(
            identifier: Self.joinActionIdentifier,
            title: "Join & Open Wikily",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [joinAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        observe()
    }

    /// Re-armed on every fire, matching `MenuBarController.observePhase()`.
    private func observe() {
        withObservationTracking {
            _ = coordinator.upcomingEvents
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observe()
            }
        }
        reconcile()
    }

    /// Schedule reminders for events that need one and don't have one yet;
    /// cancel ones whose event disappeared (cancelled meeting, disconnected
    /// account, edited to drop its join link) or whose start time has passed.
    func reconcile() {
        guard settings.meetingRemindersEnabled else {
            cancelAll()
            return
        }

        let candidates = coordinator.upcomingEvents.filter { event in
            !event.isAllDay && event.joinURL != nil && event.startDate > now()
        }

        var desired: Set<String> = []
        for event in candidates {
            let identifier = Self.identifier(for: event)
            desired.insert(identifier)
            guard !scheduledIdentifiers.contains(identifier) else { continue }
            guard let fireDate = MeetingReminderPlan.fireDate(
                eventStart: event.startDate, now: now(), leadTime: leadTime
            ) else { continue }
            schedule(event: event, identifier: identifier, fireDate: fireDate)
        }

        let stale = scheduledIdentifiers.subtracting(desired)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        scheduledIdentifiers = desired
    }

    private func cancelAll() {
        guard !scheduledIdentifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(scheduledIdentifiers))
        scheduledIdentifiers = []
    }

    private func schedule(event: CalendarEvent, identifier: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.title) starts in 1 minute"
        content.body = "Join now and Wikily will be ready to help."
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.userInfo = [Self.joinURLUserInfoKey: event.joinURL?.absoluteString ?? ""]

        let interval = max(fireDate.timeIntervalSince(now()), 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let logger = self.logger
        center.add(request) { error in
            if let error {
                logger.error("""
                    Couldn't schedule meeting reminder: \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
    }

    static func identifier(for event: CalendarEvent) -> String {
        "\(categoryIdentifier).\(event.id)"
    }
}
