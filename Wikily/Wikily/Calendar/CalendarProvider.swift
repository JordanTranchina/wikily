import Foundation

/// A calendar service Wikily can connect to for meeting reminders.
///
/// Two cases because those are the two the product asked for, not because the
/// rest of this module is written to make a third one free — `CalendarProviderClient`
/// exists so adding one is "write a client", not "touch the sync coordinator".
enum CalendarProvider: String, Sendable, CaseIterable, Codable, Identifiable {
    case google
    case outlook

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: "Google Calendar"
        case .outlook: "Outlook Calendar"
        }
    }

    /// SF Symbol for the connect button and the account row. Both providers
    /// share one glyph — Wikily draws its own accent color per row instead of
    /// carrying a bitmap logo for each service.
    var symbol: String { "calendar" }
}
