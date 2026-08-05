import Foundation
import OSLog

/// Connected calendar accounts: who's connected, and the OAuth dance for
/// connecting and disconnecting one.
///
/// `@MainActor @Observable`, matching `AppSettings` and `CallSession` — the
/// Calendar settings tab binds to `accounts` directly. Metadata (provider,
/// email, connected date) persists through `AppSettings` like everything else
/// Wikily remembers; tokens never touch `UserDefaults` — see
/// `CalendarTokenStoring`.
@MainActor
@Observable
final class CalendarAccountStore {

    static let shared = CalendarAccountStore()

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "CalendarAccountStore")

    private(set) var accounts: [CalendarAccount]
    var connectionError: String?
    private(set) var isConnecting = false

    private let settings: AppSettings
    private let tokenStore: any CalendarTokenStoring
    private let browser: any OAuthBrowserPresenting
    private let clients: [CalendarProvider: any CalendarProviderClient]

    init(
        settings: AppSettings = .shared,
        tokenStore: any CalendarTokenStoring = KeychainCalendarTokenStore(),
        browser: any OAuthBrowserPresenting = ASWebAuthenticationBrowserSession(),
        clients: [CalendarProvider: any CalendarProviderClient] = [
            .google: GoogleCalendarClient(),
            .outlook: OutlookCalendarClient(),
        ]
    ) {
        self.settings = settings
        self.tokenStore = tokenStore
        self.browser = browser
        self.clients = clients
        self.accounts = settings.connectedCalendarAccounts
    }

    /// Whether Settings should let the user click "Connect" for this
    /// provider at all — a client ID must be configured first.
    func isConfigured(_ provider: CalendarProvider) -> Bool {
        !clientID(for: provider).isEmpty
    }

    private func clientID(for provider: CalendarProvider) -> String {
        switch provider {
        case .google: settings.googleCalendarClientID
        case .outlook: settings.outlookCalendarClientID
        }
    }

    // MARK: - Connect / disconnect

    /// Run the full OAuth dance for `provider` and add the resulting account.
    ///
    /// Reconnecting the same email replaces the existing entry (and its
    /// tokens) rather than adding a duplicate — the common case this handles
    /// is a revoked-then-regranted consent, not two accounts with the same
    /// address.
    func connect(_ provider: CalendarProvider) async {
        guard let client = clients[provider] else { return }
        let clientID = clientID(for: provider)
        guard !clientID.isEmpty else {
            connectionError = "Add a \(provider.displayName) client ID below first."
            return
        }

        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            let pkce = OAuthPKCE()
            guard let authURL = client.authorizationURL(
                clientID: clientID, pkce: pkce, redirectURI: CalendarOAuthConstants.redirectURI
            ) else {
                throw CalendarOAuthError.notConfigured
            }

            let callbackURL = try await browser.authenticate(
                url: authURL,
                callbackScheme: CalendarOAuthConstants.redirectScheme
            )
            let code = try Self.code(from: callbackURL, expectedState: pkce.state)
            let tokenResponse = try await client.exchangeCode(
                code, clientID: clientID, pkce: pkce, redirectURI: CalendarOAuthConstants.redirectURI
            )
            guard let refreshToken = tokenResponse.refreshToken else {
                throw CalendarOAuthError.missingRefreshToken
            }

            let email = try await client.fetchAccountEmail(accessToken: tokenResponse.accessToken)

            let existingID = accounts.first { $0.provider == provider && $0.email == email }?.id
            let account = CalendarAccount(id: existingID ?? UUID(), provider: provider, email: email)

            try tokenStore.save(
                CalendarOAuthTokens(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                ),
                for: account.id
            )

            accounts.removeAll { $0.provider == provider && $0.email == email }
            accounts.append(account)
            persistAccounts()
        } catch OAuthBrowserError.cancelled {
            // The user closed the sheet — not a failure worth surfacing.
        } catch {
            logger.error("Calendar connect failed: \(error.localizedDescription, privacy: .public)")
            connectionError = "Couldn't connect \(provider.displayName): \(error.localizedDescription)"
        }
    }

    func disconnect(_ account: CalendarAccount) {
        accounts.removeAll { $0.id == account.id }
        persistAccounts()
        try? tokenStore.delete(for: account.id)
    }

    private func persistAccounts() {
        settings.connectedCalendarAccounts = accounts
    }

    /// Extract `code` from the redirect, verifying `state` first — the
    /// callback URL is the one part of this flow that arrives from outside
    /// the app's control, and `state` is what stops a URL crafted by
    /// something other than the authorization request Wikily just started
    /// from being accepted.
    static func code(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { throw CalendarOAuthError.malformedCallback }

        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value
            throw CalendarOAuthError.authorizationDenied(description ?? error)
        }
        guard let state = items.first(where: { $0.name == "state" })?.value, state == expectedState else {
            throw CalendarOAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw CalendarOAuthError.malformedCallback
        }
        return code
    }

    // MARK: - Fetching events with transparent token refresh

    /// Refreshes the access token first when it's within a minute of expiry
    /// (or already expired) rather than waiting for the API to reject it —
    /// `CalendarSyncCoordinator` polls on a one-minute cadence too, so
    /// "refresh on 401" would routinely cost a whole cycle right when a
    /// reminder is due.
    func fetchEvents(for account: CalendarAccount, from: Date, to: Date) async throws -> [CalendarEvent] {
        guard let client = clients[account.provider] else { return [] }
        guard var tokens = try tokenStore.load(for: account.id) else {
            throw CalendarOAuthError.notConnected
        }

        if tokens.expiresAt <= Date().addingTimeInterval(60) {
            let refreshed = try await client.refreshTokens(
                clientID: clientID(for: account.provider),
                refreshToken: tokens.refreshToken
            )
            tokens = CalendarOAuthTokens(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? tokens.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
            )
            try tokenStore.save(tokens, for: account.id)
        }

        return try await client.fetchUpcomingEvents(
            accessToken: tokens.accessToken,
            accountID: account.id,
            from: from,
            to: to
        )
    }
}
