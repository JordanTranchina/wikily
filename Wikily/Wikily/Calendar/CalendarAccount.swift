import Foundation

/// One calendar account the user has connected, as far as the rest of the app
/// needs to know.
///
/// Deliberately carries no token: those live in `CalendarTokenStoring` (the
/// system Keychain), never in `UserDefaults` alongside this metadata. Splitting
/// secret from non-secret this way is what lets `AppSettings` persist the
/// account list the same way it persists everything else, while the actual
/// credential sits behind a stronger guarantee than a non-sandboxed app's flat
/// defaults domain offers.
struct CalendarAccount: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let provider: CalendarProvider
    let email: String
    let connectedAt: Date

    init(id: UUID = UUID(), provider: CalendarProvider, email: String, connectedAt: Date = Date()) {
        self.id = id
        self.provider = provider
        self.email = email
        self.connectedAt = connectedAt
    }
}
