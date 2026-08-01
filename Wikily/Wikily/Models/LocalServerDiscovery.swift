import Foundation
import OSLog

/// The three servers Wikily knows how to find without being told.
///
/// Each ships with a well-known default port and each exposes the same
/// OpenAI-compatible surface, so the port is the entire difference between them
/// as far as this app is concerned. Nothing else in the codebase branches on
/// which one it is talking to — the kind exists to put a recognisable name in
/// the picker and a useful sentence in an error, not to switch behaviour.
enum LocalServerKind: String, Sendable, CaseIterable, Codable {
    case ollama
    case lmStudio
    case llamaCpp

    var port: Int {
        switch self {
        case .ollama: 11434
        case .lmStudio: 1234
        case .llamaCpp: 8080
        }
    }

    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .llamaCpp: "llama.cpp"
        }
    }

    /// Loopback by literal IP rather than `localhost`. On a Mac where `localhost`
    /// resolves to `::1` first, connecting to an IPv4-only listener costs a DNS
    /// round trip and a failed connection before the fallback — enough to blow a
    /// one-second probe budget on a server that is in fact running.
    var defaultBaseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Best-effort identification of a user-entered URL, for labelling only.
    init?(baseURL: URL) {
        guard let port = baseURL.port,
              let match = Self.allCases.first(where: { $0.port == port })
        else { return nil }
        self = match
    }
}

/// A local server that answered, and what it offers.
struct LocalServerEndpoint: Sendable, Hashable, Identifiable {

    /// `nil` when the user pointed Wikily at a non-standard port.
    let kind: LocalServerKind?
    let baseURL: URL

    /// Model names exactly as the server reports them, in its own order —
    /// which for Ollama is most-recently-used first, and is more useful to a
    /// picker than anything we could re-sort them into.
    let models: [String]

    var id: String { baseURL.absoluteString }

    var displayName: String {
        kind?.displayName ?? baseURL.host.map { "\($0):\(baseURL.port ?? 80)" } ?? "Local server"
    }

    /// Picker rows for this server, one per model.
    var descriptors: [ModelDescriptor] {
        models.map {
            ModelDescriptor.localServer(baseURL: baseURL, modelID: $0, serverName: displayName)
        }
    }
}

/// Finds local model servers so the user never has to type a URL.
///
/// The design constraint is that this runs at launch, in front of a UI that must
/// not wait for it. Everything follows from that: probes run in parallel, the
/// timeout is a second, and a port that doesn't answer costs nothing because a
/// refused loopback connection fails immediately rather than timing out. The
/// slow case — a port held open by something that isn't a model server — is the
/// only one the timeout is really for.
///
/// A server is "found" only if `/v1/models` returns a decodable list. Port 8080
/// in particular is contested territory on a developer's machine; anything that
/// merely accepts a connection there would otherwise show up in the picker as a
/// model server and fail later, in the middle of a call.
enum LocalServerDiscovery {

    private static let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "LocalServerDiscovery"
    )

    /// Probe every well-known port at once.
    ///
    /// Returns in `LocalServerKind.allCases` order rather than completion order,
    /// so the picker doesn't reshuffle itself between launches based on which
    /// server happened to answer first.
    static func probeAll(
        timeout: TimeInterval = 1,
        session: URLSession? = nil
    ) async -> [LocalServerEndpoint] {
        let session = session ?? makeSession(timeout: timeout)
        let kinds = LocalServerKind.allCases

        let found = await withTaskGroup(
            of: (Int, LocalServerEndpoint?).self
        ) { group -> [Int: LocalServerEndpoint] in
            for (offset, kind) in kinds.enumerated() {
                group.addTask {
                    (offset, await probe(baseURL: kind.defaultBaseURL, session: session))
                }
            }
            var results: [Int: LocalServerEndpoint] = [:]
            for await (offset, endpoint) in group {
                results[offset] = endpoint
            }
            return results
        }

        let endpoints = kinds.indices.compactMap { found[$0] }
        logger.info("""
            Local server probe found \(endpoints.count, privacy: .public) of \
            \(kinds.count, privacy: .public): \
            \(endpoints.map(\.displayName).joined(separator: ", "), privacy: .public)
            """)
        return endpoints
    }

    /// Probe one base URL. `nil` means "not a usable model server", which
    /// covers connection refused, a timeout, a non-2xx status, and a body that
    /// isn't a model list — all of which mean the same thing to the caller.
    static func probe(
        baseURL: URL,
        session: URLSession? = nil,
        timeout: TimeInterval = 1
    ) async -> LocalServerEndpoint? {
        let session = session ?? makeSession(timeout: timeout)
        do {
            let models = try await models(at: baseURL, session: session)
            return LocalServerEndpoint(
                kind: LocalServerKind(baseURL: baseURL),
                baseURL: baseURL,
                models: models
            )
        } catch {
            return nil
        }
    }

    /// Models a server reports at `GET /v1/models`.
    static func models(at baseURL: URL, session: URLSession) async throws -> [String] {
        var request = URLRequest(url: LocalServerEndpoints.models(baseURL: baseURL))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ModelServiceError.httpStatus(code: http.statusCode, body: nil)
        }
        return try parseModelList(data)
    }

    /// Decode an OpenAI-style `/v1/models` body.
    ///
    /// Kept pure and separate so the shape can be tested against captured
    /// payloads from all three servers with nothing listening.
    ///
    /// Entries whose `id` is missing or empty are dropped rather than failing the
    /// whole list: a single odd entry shouldn't hide every other model the user
    /// has. An entirely undecodable body *does* throw, because that is the signal
    /// that whatever is on this port is not a model server.
    static func parseModelList(_ data: Data) throws -> [String] {
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return list.data.compactMap { entry in
            guard let id = entry.id, !id.isEmpty else { return nil }
            return id
        }
    }

    private struct ModelList: Decodable {
        struct Entry: Decodable {
            let id: String?
        }
        let data: [Entry]
    }

    /// Short timeouts and no connectivity waiting: this must fail fast, and
    /// `waitsForConnectivity` would otherwise park a probe for the full resource
    /// timeout when the machine thinks it is offline — even though the target is
    /// loopback and offline is irrelevant.
    static func makeSession(timeout: TimeInterval = 1) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        return URLSession(configuration: config)
    }
}
