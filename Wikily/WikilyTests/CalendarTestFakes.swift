import Foundation
import UserNotifications
@testable import Wikily

/// Shared calendar-feature test doubles — used by `CalendarAccountStoreTests`,
/// `CalendarSyncCoordinatorTests`, and `MeetingNotificationSchedulerTests`, so
/// the OAuth dance, the sync loop, and the reminder scheduler can all be
/// exercised without Google, Microsoft, a real browser sheet, the Keychain, or
/// `UNUserNotificationCenter`.

/// Records the authorization URL it was asked to present, and hands back
/// either a crafted callback URL (echoing the `state` it was given, the way a
/// real redirect would) or a configured failure — never a real browser sheet.
@MainActor
final class FakeOAuthBrowserSession: OAuthBrowserPresenting {

    enum Mode {
        case echoState(code: String)
        case failure(any Error)
    }

    var mode: Mode = .echoState(code: "fake-code")
    private(set) var lastRequestedURL: URL?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        lastRequestedURL = url
        switch mode {
        case .failure(let error):
            throw error
        case .echoState(let code):
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            var components = URLComponents(
                url: CalendarOAuthConstants.redirectURI, resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: state),
            ]
            return components.url!
        }
    }
}

/// A `CalendarProviderClient` with every response canned, so the OAuth dance
/// and the sync path can be tested without Google, Microsoft, or the network.
final class FakeCalendarProviderClient: CalendarProviderClient, @unchecked Sendable {

    let provider: CalendarProvider

    var exchangeCodeResult: Result<OAuthTokenResponse, any Error> = .success(
        OAuthTokenResponse(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 3600)
    )
    var refreshTokensResult: Result<OAuthTokenResponse, any Error> = .success(
        OAuthTokenResponse(accessToken: "access-2", refreshToken: nil, expiresIn: 3600)
    )
    var fetchAccountEmailResult: Result<String, any Error> = .success("person@example.com")
    var fetchUpcomingEventsResult: Result<[CalendarEvent], any Error> = .success([])

    private(set) var refreshTokensCallCount = 0
    private(set) var fetchUpcomingEventsCallCount = 0

    init(provider: CalendarProvider) {
        self.provider = provider
    }

    func authorizationURL(clientID: String, pkce: OAuthPKCE, redirectURI: URL) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(string: "https://example.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url
    }

    func exchangeCode(
        _ code: String, clientID: String, pkce: OAuthPKCE, redirectURI: URL
    ) async throws -> OAuthTokenResponse {
        try exchangeCodeResult.get()
    }

    func refreshTokens(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse {
        refreshTokensCallCount += 1
        return try refreshTokensResult.get()
    }

    func fetchAccountEmail(accessToken: String) async throws -> String {
        try fetchAccountEmailResult.get()
    }

    func fetchUpcomingEvents(
        accessToken: String, accountID: UUID, from: Date, to: Date
    ) async throws -> [CalendarEvent] {
        fetchUpcomingEventsCallCount += 1
        return try fetchUpcomingEventsResult.get()
    }
}

/// Records every category/request/cancellation `MeetingNotificationScheduler`
/// asks for, without touching the real notification center.
final class FakeNotificationCenter: UNUserNotificationCenterProviding, @unchecked Sendable {
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var pendingRequests: [String: UNNotificationRequest] = [:]
    private(set) var removedIdentifiers: [[String]] = []

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        pendingRequests[request.identifier] = request
        completionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        for identifier in identifiers {
            pendingRequests.removeValue(forKey: identifier)
        }
    }
}
