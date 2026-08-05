import Foundation

/// The one redirect URI every provider client and the Azure/Google Cloud app
/// registrations in `docs/CALENDAR_INTEGRATION.md` have to agree on.
///
/// A custom URL scheme rather than a `https://` redirect: Wikily has no
/// backend to host a redirect page on, and `ASWebAuthenticationSession`
/// intercepts a scheme it's told to watch for without needing one. Registered
/// in `CFBundleURLTypes` (see `SparkleInfo.plist`) as a fallback for the OS to
/// route the callback to Wikily at all.
enum CalendarOAuthConstants {
    static let redirectURI = URL(string: "wikily://oauth-callback")!
    static var redirectScheme: String { redirectURI.scheme ?? "wikily" }
}
