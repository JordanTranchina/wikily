import Foundation

/// Outlook / Microsoft 365 calendars via the Microsoft identity platform
/// (Authorization Code + PKCE, public client — no client secret) and
/// Microsoft Graph.
///
/// Registered the same way as the Google client: a "public client" app
/// registration in the Azure Portal, redirect URI `wikily://oauth-callback`,
/// client ID pasted into Settings › Calendar. See
/// `docs/CALENDAR_INTEGRATION.md`.
struct OutlookCalendarClient: CalendarProviderClient {

    let provider: CalendarProvider = .outlook
    private let session: URLSession

    init(session: URLSession = CalendarHTTP.makeSession()) {
        self.session = session
    }

    /// The `common` tenant accepts both personal Microsoft accounts and work/
    /// school accounts — Wikily has no way to know in advance which kind a
    /// user has, and `common` is Microsoft's answer for exactly that.
    private static let authorizationEndpoint =
        URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
    private static let tokenEndpoint =
        URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
    private static let meEndpoint = URL(string: "https://graph.microsoft.com/v1.0/me")!
    private static let calendarViewEndpoint =
        URL(string: "https://graph.microsoft.com/v1.0/me/calendarview")!

    /// `offline_access` is what earns a refresh token back at all — Microsoft
    /// omits it by default, unlike Google. `Calendars.Read` is read-only:
    /// Wikily never writes to a calendar. `User.Read` is only for resolving
    /// the account's own email to label the connection in Settings.
    private static let scope = "offline_access Calendars.Read User.Read"

    // MARK: - Authorization

    func authorizationURL(clientID: String, pkce: OAuthPKCE, redirectURI: URL) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components?.url
    }

    func exchangeCode(
        _ code: String,
        clientID: String,
        pkce: OAuthPKCE,
        redirectURI: URL
    ) async throws -> OAuthTokenResponse {
        guard !clientID.isEmpty else { throw CalendarOAuthError.notConfigured }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: pkce.codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        return try await postForm(to: Self.tokenEndpoint, form: form)
    }

    func refreshTokens(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse {
        guard !clientID.isEmpty else { throw CalendarOAuthError.notConfigured }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        return try await postForm(to: Self.tokenEndpoint, form: form)
    }

    private func postForm(to url: URL, form: URLComponents) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        try CalendarHTTP.checkStatus(response, data: data)
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    // MARK: - Account

    func fetchAccountEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: Self.meEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try CalendarHTTP.checkStatus(response, data: data)
        return try Self.parseEmail(data)
    }

    /// `mail` is unset for some work/school accounts that only have a login
    /// UPN, so this falls back to `userPrincipalName` rather than failing —
    /// that value is what the account actually signs in with, and unlike
    /// `mail` it's always populated.
    static func parseEmail(_ data: Data) throws -> String {
        let profile = try JSONDecoder().decode(GraphProfile.self, from: data)
        guard let email = profile.mail ?? profile.userPrincipalName else {
            throw CalendarOAuthError.malformedCallback
        }
        return email
    }

    private struct GraphProfile: Decodable {
        let mail: String?
        let userPrincipalName: String?
    }

    // MARK: - Events

    func fetchUpcomingEvents(
        accessToken: String,
        accountID: UUID,
        from: Date,
        to: Date
    ) async throws -> [CalendarEvent] {
        var components = URLComponents(url: Self.calendarViewEndpoint, resolvingAgainstBaseURL: false)!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: iso.string(from: from)),
            URLQueryItem(name: "endDateTime", value: iso.string(from: to)),
            URLQueryItem(name: "$top", value: "50"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // Graph otherwise returns `start`/`end` in whatever timezone the
        // account's mailbox settings default to, which varies per user and
        // would silently misplace the reminder. Requesting UTC explicitly is
        // what makes `GraphDateTimeParsing` safe to treat every timestamp as
        // UTC without inspecting the accompanying `timeZone` field per-event.
        request.setValue(#"outlook.timezone="UTC""#, forHTTPHeaderField: "Prefer")

        let (data, response) = try await session.data(for: request)
        try CalendarHTTP.checkStatus(response, data: data)
        return try Self.parseEvents(data, accountID: accountID)
    }

    // MARK: - Response decoding

    /// Kept pure and separate from the network call so the shape can be
    /// tested against a captured payload with nothing listening.
    static func parseEvents(_ data: Data, accountID: UUID) throws -> [CalendarEvent] {
        let list = try JSONDecoder().decode(EventList.self, from: data)
        return list.value.compactMap { normalize($0, accountID: accountID) }
    }

    private static func normalize(_ event: GraphEvent, accountID: UUID) -> CalendarEvent? {
        guard event.isCancelled != true else { return nil }
        guard
            let startValue = event.start?.dateTime, let start = GraphDateTimeParsing.date(from: startValue),
            let endValue = event.end?.dateTime, let end = GraphDateTimeParsing.date(from: endValue)
        else { return nil }

        return CalendarEvent(
            providerEventID: event.id,
            accountID: accountID,
            provider: .outlook,
            title: event.subject ?? "(No title)",
            startDate: start,
            endDate: end,
            isAllDay: event.isAllDay ?? false,
            joinURL: MeetingLinkExtractor.joinURL(in: [
                event.onlineMeeting?.joinUrl,
                event.onlineMeetingUrl,
                event.location?.displayName,
                event.bodyPreview,
            ])
        )
    }

    private struct EventList: Decodable {
        let value: [GraphEvent]
    }

    private struct GraphEvent: Decodable {
        struct DateTimeTimeZone: Decodable {
            let dateTime: String?
        }
        struct OnlineMeeting: Decodable {
            let joinUrl: String?
        }
        struct Location: Decodable {
            let displayName: String?
        }
        let id: String
        let subject: String?
        let isAllDay: Bool?
        let isCancelled: Bool?
        let start: DateTimeTimeZone?
        let end: DateTimeTimeZone?
        let location: Location?
        let bodyPreview: String?
        let onlineMeetingUrl: String?
        let onlineMeeting: OnlineMeeting?
    }
}
