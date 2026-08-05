import Foundation

/// Google Calendar via the installed-app OAuth flow (Authorization Code +
/// PKCE, no client secret) and Calendar API v3.
///
/// The client ID itself is not a secret — Google's own guidance for installed
/// apps says so — but it is still per-app, and Wikily doesn't ship one of its
/// own: whoever builds Wikily (or a user building it themselves) creates a
/// "Desktop app" OAuth client in Google Cloud Console and pastes the ID into
/// Settings › Calendar. See `docs/CALENDAR_INTEGRATION.md`.
struct GoogleCalendarClient: CalendarProviderClient {

    let provider: CalendarProvider = .google
    private let session: URLSession

    init(session: URLSession = CalendarHTTP.makeSession()) {
        self.session = session
    }

    private static let authorizationEndpoint =
        URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    private static let eventsEndpoint =
        URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!

    /// Read-only calendar access plus the email address needed to label the
    /// connected account — nothing else. Wikily never writes to a calendar.
    private static let scope =
        "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/userinfo.email"

    // MARK: - Authorization

    func authorizationURL(clientID: String, pkce: OAuthPKCE, redirectURI: URL) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            // `offline` + `consent` together are what guarantee a refresh
            // token comes back even on a second connect from the same Google
            // account — without `consent`, a user who previously granted
            // access gets silently re-approved with no refresh token at all.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
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
        var request = URLRequest(url: Self.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try CalendarHTTP.checkStatus(response, data: data)
        return try JSONDecoder().decode(UserInfo.self, from: data).email
    }

    private struct UserInfo: Decodable {
        let email: String
    }

    // MARK: - Events

    func fetchUpcomingEvents(
        accessToken: String,
        accountID: UUID,
        from: Date,
        to: Date
    ) async throws -> [CalendarEvent] {
        var components = URLComponents(url: Self.eventsEndpoint, resolvingAgainstBaseURL: false)!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try CalendarHTTP.checkStatus(response, data: data)
        return try Self.parseEvents(data, accountID: accountID)
    }

    // MARK: - Response decoding

    /// Kept pure and separate from the network call so the shape can be
    /// tested against a captured payload with nothing listening — the same
    /// reasoning as `LocalServerDiscovery.parseModelList`.
    static func parseEvents(_ data: Data, accountID: UUID) throws -> [CalendarEvent] {
        let list = try JSONDecoder().decode(EventList.self, from: data)
        return list.items.compactMap { normalize($0, accountID: accountID) }
    }

    private static func normalize(_ event: GoogleEvent, accountID: UUID) -> CalendarEvent? {
        // Cancelled instances of a recurring series still come back from
        // `singleEvents=true`; a reminder for a meeting that was cancelled is
        // worse than no reminder.
        guard event.status != "cancelled" else { return nil }
        guard let title = event.summary else { return nil }
        guard let start = parseDate(event.start), let end = parseDate(event.end) else { return nil }

        let conferenceURI = event.conferenceData?.entryPoints?
            .first { $0.entryPointType == "video" }?.uri

        return CalendarEvent(
            providerEventID: event.id,
            accountID: accountID,
            provider: .google,
            title: title,
            startDate: start,
            endDate: end,
            // A dateless `start.date` (as opposed to `start.dateTime`) is
            // Google's shape for an all-day event.
            isAllDay: event.start?.dateTime == nil,
            joinURL: MeetingLinkExtractor.joinURL(in: [
                event.hangoutLink,
                conferenceURI,
                event.location,
                event.description,
            ])
        )
    }

    private static func parseDate(_ dateTime: GoogleEvent.EventDateTime?) -> Date? {
        guard let dateTime else { return nil }
        if let value = dateTime.dateTime {
            return RFC3339DateParsing.date(from: value)
        }
        if let date = dateTime.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: date)
        }
        return nil
    }

    private struct EventList: Decodable {
        let items: [GoogleEvent]
    }

    private struct GoogleEvent: Decodable {
        struct EventDateTime: Decodable {
            let dateTime: String?
            let date: String?
        }
        struct ConferenceData: Decodable {
            struct EntryPoint: Decodable {
                let entryPointType: String?
                let uri: String?
            }
            let entryPoints: [EntryPoint]?
        }
        let id: String
        let status: String?
        let summary: String?
        let start: EventDateTime?
        let end: EventDateTime?
        let location: String?
        let description: String?
        let hangoutLink: String?
        let conferenceData: ConferenceData?
    }
}
