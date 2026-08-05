import AppKit
import AuthenticationServices

enum OAuthBrowserError: Error, LocalizedError {
    case cancelled
    case noCallbackURL

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .noCallbackURL: "Sign-in finished without returning to Wikily."
        }
    }
}

/// Presents the system browser sheet for one OAuth authorization request and
/// hands back the redirect URL.
///
/// A protocol wrapping `ASWebAuthenticationSession` rather than
/// `CalendarAccountStore` calling it directly, for the same reason
/// `LaunchAtLoginControl` wraps `SMAppService`: nothing in a test suite should
/// be popping a real system browser sheet, and a fake implementation is what
/// lets the rest of the OAuth dance — state checking, token exchange, account
/// persistence — be tested without one.
@MainActor
protocol OAuthBrowserPresenting {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The real thing: a `.nonactivatingPanel`-style system sheet backed by the
/// user's default browser and its existing cookies, so a user already signed
/// into Google or Microsoft doesn't have to re-enter a password to connect a
/// calendar.
///
/// Wikily declares the `wikily` URL scheme in `CFBundleURLTypes` (see
/// `SparkleInfo.plist`) as a fallback for the redirect, but
/// `ASWebAuthenticationSession` intercepts a matching callback URL directly —
/// this never needs `AppDelegate` to implement `application(_:open:)`.
@MainActor
final class ASWebAuthenticationBrowserSession: NSObject, OAuthBrowserPresenting {

    /// Retained for the lifetime of one `authenticate(url:callbackScheme:)`
    /// call — `ASWebAuthenticationSession` does not retain itself, and a
    /// session that deallocates mid-flow silently never calls back.
    private var currentSession: ASWebAuthenticationSession?
    private let contextProvider = PresentationContextProvider()

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: OAuthBrowserError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthBrowserError.noCallbackURL)
                }
            }
            session.presentationContextProvider = contextProvider
            currentSession = session
            session.start()
        }
    }

    private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        /// The Settings window is what the user just clicked "Connect" in, so
        /// it is almost always the key window here — the fallbacks exist only
        /// for the case Settings was somehow closed mid-click.
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
