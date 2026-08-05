import Foundation

/// Wire-format tokens from either provider's token endpoint. Both Google and
/// Microsoft use the same OAuth2 token-response shape.
struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    /// Omitted on some responses — a token refresh, or a re-consent Google
    /// treats as a repeat grant — where the existing refresh token is still
    /// valid and simply isn't reissued.
    let refreshToken: String?
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum CalendarOAuthError: Error, LocalizedError, Equatable {
    case notConfigured
    case notConnected
    case malformedCallback
    case stateMismatch
    case missingRefreshToken
    case authorizationDenied(String)
    case httpStatus(code: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No client ID is configured for this provider."
        case .notConnected:
            "This account isn't connected."
        case .malformedCallback:
            "The sign-in redirect was missing required data."
        case .stateMismatch:
            "The sign-in redirect didn't match the request that started it."
        case .missingRefreshToken:
            "Didn't receive a refresh token — try disconnecting and reconnecting."
        case .authorizationDenied(let reason):
            "Sign-in was denied: \(reason)"
        case .httpStatus(let code, let body):
            "Request failed (\(code))" + (body.map { ": \($0)" } ?? "")
        }
    }
}

/// What Wikily needs from a calendar provider, independent of which one.
///
/// Both Google and Microsoft speak OAuth 2.0 Authorization Code + PKCE with
/// near-identical shapes; this protocol is not an abstraction over some
/// hypothetical third provider — it is what lets `CalendarAccountStore` and
/// `CalendarSyncCoordinator` be written once instead of twice, and lets both
/// be tested against a fake client instead of a live Google or Microsoft
/// account.
///
/// `clientID` is a parameter on every call rather than baked into the client
/// at construction, because the user can edit it in Settings at any time —
/// `CalendarAccountStore` reads the current value out of `AppSettings` right
/// before each call rather than a client capturing a value that could go
/// stale.
protocol CalendarProviderClient: Sendable {
    var provider: CalendarProvider { get }

    /// `nil` when `clientID` is empty — `CalendarAccountStore` checks this
    /// before starting the browser flow so "Connect" fails with a clear
    /// message instead of opening a browser to an authorization URL missing
    /// its `client_id`.
    func authorizationURL(clientID: String, pkce: OAuthPKCE, redirectURI: URL) -> URL?

    func exchangeCode(
        _ code: String,
        clientID: String,
        pkce: OAuthPKCE,
        redirectURI: URL
    ) async throws -> OAuthTokenResponse

    func refreshTokens(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse

    func fetchAccountEmail(accessToken: String) async throws -> String

    /// - Parameter accountID: stamped onto every returned `CalendarEvent` —
    ///   the client has no other way to know which connected account it's
    ///   fetching for.
    func fetchUpcomingEvents(
        accessToken: String,
        accountID: UUID,
        from: Date,
        to: Date
    ) async throws -> [CalendarEvent]
}

/// Shared HTTP plumbing both provider clients build on.
enum CalendarHTTP {
    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        throw CalendarOAuthError.httpStatus(code: http.statusCode, body: String(data: data, encoding: .utf8))
    }

    /// Short timeouts, no connectivity waiting: these are interactive calls
    /// made while a Settings window or the reminder scheduler is waiting on
    /// them, not a background bulk sync.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}
