import Foundation
import Testing
@testable import Wikily

@MainActor
struct CalendarAccountStoreTests {

    private func makeSettings() -> AppSettings {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return AppSettings(defaults: defaults, launchAtLogin: .inert)
    }

    private func makeStore(
        settings: AppSettings,
        browser: FakeOAuthBrowserSession = FakeOAuthBrowserSession(),
        client: FakeCalendarProviderClient = FakeCalendarProviderClient(provider: .google),
        tokenStore: InMemoryCalendarTokenStore = InMemoryCalendarTokenStore()
    ) -> CalendarAccountStore {
        CalendarAccountStore(
            settings: settings,
            tokenStore: tokenStore,
            browser: browser,
            clients: [.google: client, .outlook: FakeCalendarProviderClient(provider: .outlook)]
        )
    }

    // MARK: - `code(from:expectedState:)`

    @Test func extractsTheCodeWhenStateMatches() throws {
        let url = URL(string: "wikily://oauth-callback?code=abc123&state=xyz")!
        #expect(try CalendarAccountStore.code(from: url, expectedState: "xyz") == "abc123")
    }

    @Test func rejectsAMismatchedState() {
        let url = URL(string: "wikily://oauth-callback?code=abc123&state=wrong")!
        #expect(throws: CalendarOAuthError.stateMismatch) {
            try CalendarAccountStore.code(from: url, expectedState: "xyz")
        }
    }

    @Test func surfacesAnAuthorizationDeniedError() {
        let url = URL(string: "wikily://oauth-callback?error=access_denied&error_description=nope&state=xyz")!
        #expect(throws: CalendarOAuthError.authorizationDenied("nope")) {
            try CalendarAccountStore.code(from: url, expectedState: "xyz")
        }
    }

    @Test func rejectsACallbackWithNoQueryItems() {
        let url = URL(string: "wikily://oauth-callback")!
        #expect(throws: CalendarOAuthError.malformedCallback) {
            try CalendarAccountStore.code(from: url, expectedState: "xyz")
        }
    }

    // MARK: - `connect(_:)`

    @Test func connectingSucceedsAndPersistsTheAccountAndItsTokens() async throws {
        let settings = makeSettings()
        let tokenStore = InMemoryCalendarTokenStore()
        let client = FakeCalendarProviderClient(provider: .google)
        let store = makeStore(settings: settings, client: client, tokenStore: tokenStore)
        settings.googleCalendarClientID = "client-id"

        await store.connect(.google)

        #expect(store.connectionError == nil)
        let account = try #require(store.accounts.first)
        #expect(account.email == "person@example.com")
        #expect(account.provider == .google)
        #expect(settings.connectedCalendarAccounts == store.accounts)

        let tokens = try #require(try tokenStore.load(for: account.id))
        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
    }

    @Test func connectingWithNoClientIDFailsWithoutOpeningTheBrowser() async {
        let settings = makeSettings()
        let browser = FakeOAuthBrowserSession()
        let store = makeStore(settings: settings, browser: browser)

        await store.connect(.google)

        #expect(store.accounts.isEmpty)
        #expect(store.connectionError != nil)
        #expect(browser.lastRequestedURL == nil)
    }

    @Test func aMissingRefreshTokenFailsTheConnectRatherThanSavingAPartialAccount() async {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        let client = FakeCalendarProviderClient(provider: .google)
        client.exchangeCodeResult = .success(
            OAuthTokenResponse(accessToken: "access-1", refreshToken: nil, expiresIn: 3600)
        )
        let store = makeStore(settings: settings, client: client)

        await store.connect(.google)

        #expect(store.accounts.isEmpty)
        #expect(store.connectionError != nil)
    }

    @Test func reconnectingTheSameEmailReplacesRatherThanDuplicates() async throws {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        let client = FakeCalendarProviderClient(provider: .google)
        let store = makeStore(settings: settings, client: client)

        await store.connect(.google)
        let firstID = try #require(store.accounts.first?.id)

        await store.connect(.google)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == firstID)
    }

    @Test func cancellingTheBrowserSheetIsNotSurfacedAsAnError() async {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        let browser = FakeOAuthBrowserSession()
        browser.mode = .failure(OAuthBrowserError.cancelled)
        let store = makeStore(settings: settings, browser: browser)

        await store.connect(.google)

        #expect(store.accounts.isEmpty)
        #expect(store.connectionError == nil)
    }

    // MARK: - `disconnect(_:)`

    @Test func disconnectingRemovesTheAccountAndItsTokens() async throws {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        let tokenStore = InMemoryCalendarTokenStore()
        let store = makeStore(settings: settings, tokenStore: tokenStore)

        await store.connect(.google)
        let account = try #require(store.accounts.first)

        store.disconnect(account)

        #expect(store.accounts.isEmpty)
        #expect(settings.connectedCalendarAccounts.isEmpty)
        #expect(try tokenStore.load(for: account.id) == nil)
    }

    // MARK: - `isConfigured(_:)`

    @Test func isConfiguredReflectsWhetherAClientIDIsSet() {
        let settings = makeSettings()
        let store = makeStore(settings: settings)

        #expect(!store.isConfigured(.google))
        settings.googleCalendarClientID = "client-id"
        #expect(store.isConfigured(.google))
    }

    // MARK: - `fetchEvents(for:from:to:)`

    @Test func fetchEventsRefreshesAnExpiredTokenBeforeFetching() async throws {
        let settings = makeSettings()
        let tokenStore = InMemoryCalendarTokenStore()
        let client = FakeCalendarProviderClient(provider: .google)
        let account = CalendarAccount(provider: .google, email: "person@example.com")
        try tokenStore.save(
            CalendarOAuthTokens(
                accessToken: "stale-access",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(-10)
            ),
            for: account.id
        )
        let store = makeStore(settings: settings, client: client, tokenStore: tokenStore)

        _ = try await store.fetchEvents(for: account, from: Date(), to: Date().addingTimeInterval(3600))

        #expect(client.refreshTokensCallCount == 1)
        #expect(client.fetchUpcomingEventsCallCount == 1)
        let saved = try #require(try tokenStore.load(for: account.id))
        #expect(saved.accessToken == "access-2")
        // Google/Microsoft can omit a fresh refresh token on refresh; the old
        // one has to survive rather than being overwritten with `nil`.
        #expect(saved.refreshToken == "refresh-1")
    }

    @Test func fetchEventsSkipsRefreshWhenTheTokenIsStillFresh() async throws {
        let settings = makeSettings()
        let tokenStore = InMemoryCalendarTokenStore()
        let client = FakeCalendarProviderClient(provider: .google)
        let account = CalendarAccount(provider: .google, email: "person@example.com")
        try tokenStore.save(
            CalendarOAuthTokens(
                accessToken: "still-good",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            for: account.id
        )
        let store = makeStore(settings: settings, client: client, tokenStore: tokenStore)

        _ = try await store.fetchEvents(for: account, from: Date(), to: Date().addingTimeInterval(3600))

        #expect(client.refreshTokensCallCount == 0)
        #expect(client.fetchUpcomingEventsCallCount == 1)
    }

    @Test func fetchEventsThrowsForAnAccountWithNoStoredTokens() async {
        let settings = makeSettings()
        let store = makeStore(settings: settings)
        let account = CalendarAccount(provider: .google, email: "nobody@example.com")

        await #expect(throws: CalendarOAuthError.notConnected) {
            _ = try await store.fetchEvents(for: account, from: Date(), to: Date())
        }
    }
}
