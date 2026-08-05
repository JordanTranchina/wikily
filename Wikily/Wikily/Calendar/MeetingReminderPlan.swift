import Foundation

/// When to fire a "your meeting starts in 1 minute" notification for an
/// event, as a pure function of time.
///
/// Kept separate from `MeetingNotificationScheduler` for the same reason
/// `OverlayLayout` is kept separate from `OverlayWindowController`: the
/// interesting arithmetic — and its edge cases — becomes unit-testable without
/// `UNUserNotificationCenter`, which needs a signed, running app to do
/// anything at all.
enum MeetingReminderPlan {

    /// The moment a reminder for an event starting at `eventStart` should
    /// fire, or `nil` if it shouldn't be scheduled at all.
    ///
    /// - Parameter leadTime: how long before the meeting the reminder fires —
    ///   60 seconds, per the product requirement, but exposed for tests.
    ///
    /// If the one-minute-before moment has already passed but the meeting
    /// itself hasn't started — Wikily launching, or a calendar reconnecting,
    /// thirty seconds before a call — this fires almost immediately rather
    /// than not at all. A late reminder is still useful; a silently skipped
    /// one just looks broken. Once the meeting has actually started, there is
    /// nothing left to remind about, and this returns `nil`.
    static func fireDate(
        eventStart: Date,
        now: Date,
        leadTime: TimeInterval = 60
    ) -> Date? {
        let target = eventStart.addingTimeInterval(-leadTime)
        guard target > now else {
            return now < eventStart ? now.addingTimeInterval(1) : nil
        }
        return target
    }
}
