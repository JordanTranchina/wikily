import Foundation

/// The contract every model backend implements.
///
/// Two backends sit behind this: Apple's on-device foundation model, and any
/// OpenAI-compatible server the user is already running locally. Both are
/// on-device by construction — there is deliberately no cloud client here. The
/// Tauri build shipped one, and it is the reason "local-first" was a claim
/// rather than a property: the moment whisper.cpp was missing, transcripts went
/// to a remote API. Removing the possibility is the only way to keep the promise.
///
/// **Deltas, not snapshots.** Callers get incremental text and are expected to
/// append. That is the harder contract to implement — Apple's `ResponseStream`
/// hands back *cumulative* snapshots and OpenAI-style SSE hands back deltas — so
/// the normalisation happens once, in the backends, instead of at every call
/// site. `CumulativeTextDeltas` exists for the snapshot side of that.
protocol LanguageModelService: Sendable {

    /// Stable identity for persistence and for the settings picker.
    var descriptor: ModelDescriptor { get }

    /// Whether this backend can currently answer, and why not if it can't.
    ///
    /// `async` because answering honestly requires I/O for the local-server
    /// backend (something has to be listening on the port). Cheap enough to call
    /// on a settings screen; not cheap enough to call per token.
    func availability() async -> ModelAvailability

    /// Stream a completion as append-only deltas.
    ///
    /// Never `throws` synchronously — every failure, including "this backend is
    /// unavailable", arrives as the stream's terminal error. One error path is
    /// simpler for the UI than two, and availability can change between the
    /// check and the call anyway.
    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error>
}

extension LanguageModelService {

    /// Convenience for callers that want the whole answer rather than a live one.
    ///
    /// Deliberately built on `stream` rather than a separate non-streaming path,
    /// so there is one code path to get wrong.
    func complete(prompt: String, systemPrompt: String? = nil) async throws -> String {
        var output = ""
        for try await delta in stream(prompt: prompt, systemPrompt: systemPrompt) {
            output += delta
        }
        return output
    }
}

// MARK: - Availability

/// Whether a backend can answer right now, with a reason a human can act on.
///
/// The reason is a sentence, not a code, because every consumer of it is a piece
/// of UI telling the user what to do next. "Apple Intelligence is turned off in
/// System Settings" is actionable; `.unavailable(.appleIntelligenceNotEnabled)`
/// forces every call site to re-derive that sentence.
enum ModelAvailability: Sendable, Equatable {
    case available

    /// Not usable, with a user-facing explanation and, where one exists, the
    /// concrete next step.
    case unavailable(reason: String, recovery: String? = nil)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Reason plus recovery as one sentence, for a single-line status label.
    var message: String? {
        guard case .unavailable(let reason, let recovery) = self else { return nil }
        guard let recovery else { return reason }
        return "\(reason) \(recovery)"
    }
}

// MARK: - Errors

enum ModelServiceError: LocalizedError, Equatable {
    /// The backend was asked to generate while unavailable. Carries the same
    /// human-readable text `availability()` would have returned.
    case unavailable(String)

    /// The server answered, but not with success.
    case httpStatus(code: Int, body: String?)

    /// The server answered with an OpenAI-style `{"error": ...}` envelope.
    case server(message: String)

    /// The response was not the streaming format we asked for.
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                "The model server returned HTTP \(code): \(body)"
            } else {
                "The model server returned HTTP \(code)."
            }
        case .server(let message):
            message
        case .malformedResponse(let detail):
            "The model server sent an unexpected response: \(detail)"
        }
    }
}

// MARK: - Picker support

/// Identity of one selectable model, as shown in Settings.
///
/// `id` is what gets persisted, so it has to survive a restart in which the
/// user's local server is not running — which is why it encodes the backend and
/// the model name rather than pointing at a live object.
struct ModelDescriptor: Sendable, Hashable, Codable, Identifiable {

    enum Backend: String, Sendable, Codable, CaseIterable {
        case appleFoundation
        case localServer
    }

    var backend: Backend

    /// Base URL of the local server. `nil` for the Apple backend.
    var serverBaseURL: URL?

    /// Model name as the server knows it (`"gemma3:4b"`, `"qwen2.5-7b-instruct"`).
    /// `nil` for the Apple backend, which exposes exactly one model.
    var modelID: String?

    /// Short label for the picker row.
    var displayName: String

    var id: String {
        switch backend {
        case .appleFoundation:
            "apple"
        case .localServer:
            "local:\(serverBaseURL?.absoluteString ?? "?"):\(modelID ?? "?")"
        }
    }

    static let appleFoundation = ModelDescriptor(
        backend: .appleFoundation,
        displayName: "Apple Intelligence (on-device)"
    )

    static func localServer(baseURL: URL, modelID: String, serverName: String) -> ModelDescriptor {
        ModelDescriptor(
            backend: .localServer,
            serverBaseURL: baseURL,
            modelID: modelID,
            displayName: "\(modelID) — \(serverName)"
        )
    }
}

extension ModelDescriptor {

    /// Build the service a descriptor names.
    ///
    /// Returns `nil` only for a descriptor that cannot be honoured at all — a
    /// `.localServer` row that lost its URL or model between persistence and
    /// restore. Everything else, including a server that is currently down,
    /// produces a service whose `availability()` explains the problem. Degrading
    /// through the normal availability path keeps the failure visible in one
    /// place instead of two.
    func makeService(session: URLSession? = nil) -> (any LanguageModelService)? {
        switch backend {
        case .appleFoundation:
            return AppleFoundationModelService()
        case .localServer:
            guard let serverBaseURL, let modelID else { return nil }
            return LocalServerModelService(
                baseURL: serverBaseURL,
                modelID: modelID,
                displayName: displayName,
                session: session
            )
        }
    }
}

// MARK: - Snapshot → delta

/// Turns a sequence of cumulative text snapshots into append-only deltas.
///
/// Apple's `LanguageModelSession.ResponseStream` yields the whole answer so far
/// on every tick, while this layer's contract is "append this". Diffing is
/// therefore unavoidable; putting it in one tested value type is the cheapest
/// way to make sure it is done once and correctly.
///
/// The rule is *longest common prefix*, not `hasPrefix`. In the normal case the
/// two are identical, because each snapshot extends the last. The difference
/// only shows up if a backend ever revises text it already emitted, and there
/// the LCP rule still emits the changed tail rather than either dropping it
/// (silent truncation) or re-emitting the entire answer (visible duplication).
struct CumulativeTextDeltas: Sendable {

    /// Everything handed out so far. Equals the last snapshot in the normal case.
    private(set) var emitted: String = ""

    init() {}

    /// The text to append for this snapshot, or `nil` if it added nothing.
    mutating func delta(for snapshot: String) -> String? {
        guard snapshot != emitted else { return nil }

        let shared = snapshot.commonPrefix(with: emitted)
        let addition = String(snapshot.dropFirst(shared.count))
        emitted = snapshot
        return addition.isEmpty ? nil : addition
    }
}
