import Foundation

/// One calendar event, normalized across providers to what the reminder
/// scheduler and the Settings preview need — not a full mirror of either
/// provider's API shape.
struct CalendarEvent: Sendable, Equatable, Identifiable {
    /// The provider's own event id. Not unique across accounts on its own —
    /// see `id` — but stable across syncs for the same account, which is what
    /// lets the notification scheduler recognise "already reminded about this
    /// one" between refreshes.
    let providerEventID: String
    let accountID: UUID
    let provider: CalendarProvider
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    /// The join link Wikily found for this event, if any — see
    /// `MeetingLinkExtractor`. `nil` means this doesn't look like a call, and
    /// the reminder scheduler skips it: "join the meeting" has nothing to
    /// point at otherwise.
    let joinURL: URL?

    /// Namespaced by account so two accounts can't collide on the same
    /// provider event id — which happens for real on a shared calendar both
    /// accounts can see.
    var id: String { "\(accountID.uuidString)#\(providerEventID)" }
}
