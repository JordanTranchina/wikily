import Foundation
import OSLog

/// One HTTP client for every local model server the user might already have.
///
/// Ollama, LM Studio and llama.cpp's `llama-server` are three different products
/// with three different native APIs — and all three expose the same
/// OpenAI-compatible surface at `/v1/chat/completions` and `/v1/models`. Writing
/// to that shim instead of to three native clients is not laziness: it means a
/// server this file has never heard of works on day one, as long as it speaks
/// the same dialect. The port is the only thing that differs, and that is
/// `LocalServerDiscovery`'s problem, not this file's.
///
/// The user has already chosen and downloaded the model. Wikily's job is to talk
/// to it, not to manage it — there is deliberately no pull, no load, no unload.
/// Those are native-API operations and adding them would re-fragment the client.
///
/// Only loopback is ever contacted. The entitlement says `network.client`
/// because a localhost socket needs it, not because anything leaves the machine.
final class LocalServerModelService: LanguageModelService {

    private let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "LocalServerModelService"
    )

    let descriptor: ModelDescriptor

    private let baseURL: URL
    private let modelID: String
    private let temperature: Double?
    private let session: URLSession

    init(
        baseURL: URL,
        modelID: String,
        displayName: String? = nil,
        temperature: Double? = 0.3,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.temperature = temperature
        self.session = session ?? Self.makeSession()
        self.descriptor = ModelDescriptor(
            backend: .localServer,
            serverBaseURL: baseURL,
            modelID: modelID,
            displayName: displayName ?? modelID
        )
    }

    /// Generation on a 7B model can sit silent for seconds before the first
    /// token, especially on a cold load, so the *request* timeout is generous.
    /// The resource timeout is effectively off: a long answer legitimately takes
    /// minutes, and cancelling one mid-sentence is worse than waiting.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Availability

    /// Reachability of the server, phrased for the settings screen.
    ///
    /// Deliberately checks that *this* model is listed rather than only that the
    /// port answers. The realistic failure after a restart is not "server down"
    /// but "server up, model deleted", and `/v1/chat/completions` reports that as
    /// a mid-stream error long after the UI has committed to the choice.
    func availability() async -> ModelAvailability {
        let serverName = LocalServerKind(baseURL: baseURL)?.displayName ?? "the model server"
        do {
            let models = try await LocalServerDiscovery.models(at: baseURL, session: session)
            guard models.contains(modelID) else {
                return .unavailable(
                    reason: "\(serverName) is running but doesn't have “\(modelID)”.",
                    recovery: "Pick another model in Settings, or pull this one again."
                )
            }
            return .available
        } catch {
            return .unavailable(
                reason: "Nothing is answering at \(baseURL.absoluteString).",
                recovery: "Start \(serverName) and try again."
            )
        }
    }

    // MARK: - Streaming

    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        let request: URLRequest
        do {
            request = try makeChatRequest(prompt: prompt, systemPrompt: systemPrompt)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let session = self.session
        let logger = self.logger

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        // The body carries the useful part ("model not found"),
                        // so drain it rather than reporting a bare status code.
                        throw ModelServiceError.httpStatus(
                            code: http.statusCode,
                            body: try? await Self.collectBody(bytes, limit: 2048)
                        )
                    }

                    var accumulator = SSELineAccumulator()
                    var sawDataLine = false

                    // Byte-at-a-time rather than `bytes.lines`. `AsyncBytes`
                    // buffers underneath, so the cost is a loop iteration and not
                    // a syscall — and it lets the line reassembly live in a value
                    // type that tests can feed splits at every offset, which is
                    // exactly where SSE clients break.
                    for try await byte in bytes {
                        for line in accumulator.consume(CollectionOfOne(byte)) {
                            switch try ChatCompletionSSEParser.event(for: line) {
                            case .delta(let text):
                                sawDataLine = true
                                continuation.yield(text)
                            case .done:
                                sawDataLine = true
                                continuation.finish()
                                return
                            case .ignored(let wasData):
                                sawDataLine = sawDataLine || wasData
                            }
                        }
                    }

                    // llama-server closes without a final newline, so the last
                    // token is sitting in the accumulator at this point.
                    if let trailing = accumulator.flush() {
                        switch try ChatCompletionSSEParser.event(for: trailing) {
                        case .delta(let text):
                            sawDataLine = true
                            continuation.yield(text)
                        case .done:
                            sawDataLine = true
                        case .ignored(let wasData):
                            sawDataLine = sawDataLine || wasData
                        }
                    }
                    // Not one `data:` frame in the whole body means this wasn't an
                    // SSE stream — a server that ignored `"stream": true`, or
                    // something on the port that isn't a model server at all.
                    // Finishing silently would be indistinguishable from a model
                    // that had nothing to say, which is the failure mode that
                    // wastes the most of a user's time.
                    guard sawDataLine else {
                        throw ModelServiceError.malformedResponse(
                            "no server-sent events in the response body"
                        )
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    logger.error("""
                        Local model stream failed: \
                        \(error.localizedDescription, privacy: .public)
                        """)
                    continuation.finish(throwing: error)
                }
            }

            // Cancelling the Task cancels the URLSession task with it, which is
            // what actually stops the server generating.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request construction

    func makeChatRequest(prompt: String, systemPrompt: String?) throws -> URLRequest {
        var messages: [ChatMessage] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }
        messages.append(ChatMessage(role: "user", content: prompt))

        var request = URLRequest(url: LocalServerEndpoints.chatCompletions(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: modelID,
                messages: messages,
                stream: true,
                temperature: temperature
            )
        )
        return request
    }

    private static func collectBody(
        _ bytes: URLSession.AsyncBytes,
        limit: Int
    ) async throws -> String {
        var data = [UInt8]()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Wire types

struct ChatMessage: Codable, Sendable, Equatable {
    var role: String
    var content: String
}

struct ChatCompletionRequest: Codable, Sendable, Equatable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool
    var temperature: Double?
}

/// Path construction shared by the client and by discovery.
///
/// Users paste base URLs in both shapes — `http://localhost:1234` and
/// `http://localhost:1234/v1` — and appending `/v1` unconditionally produces
/// `/v1/v1/models`, which 404s with no hint as to why.
enum LocalServerEndpoints {

    /// Rebuilt from path *segments* rather than by trimming the URL.
    ///
    /// The obvious implementation — loop `deletingLastPathComponent()` while the
    /// path ends in a slash — hangs forever on `http://host:11434/`, because
    /// deleting the last component of a root path returns the same URL. The
    /// suite caught it as a spinning test process rather than a failure, which
    /// is the only reason it isn't still in here.
    static func versioned(baseURL: URL, path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()

        var segments = components.path.split(separator: "/").map(String.init)
        if segments.last != "v1" { segments.append("v1") }
        segments.append(contentsOf: path.split(separator: "/").map(String.init))
        components.path = "/" + segments.joined(separator: "/")

        return components.url ?? baseURL
    }

    static func models(baseURL: URL) -> URL {
        versioned(baseURL: baseURL, path: "models")
    }

    static func chatCompletions(baseURL: URL) -> URL {
        versioned(baseURL: baseURL, path: "chat/completions")
    }
}

// MARK: - SSE line reassembly

/// Reassembles complete lines from byte chunks that split anywhere.
///
/// The single most common bug in hand-rolled SSE clients is assuming a read
/// boundary is a line boundary. It isn't: a token's `data:` line routinely
/// arrives in two pieces, and a client that parses per-read drops one of them.
/// Keeping the partial tail in a value type makes the failure impossible to
/// reintroduce and trivial to test at every split offset.
struct SSELineAccumulator: Sendable {

    private var buffer: [UInt8] = []

    init() {}

    /// Complete lines contained in `bytes`, with any trailing partial retained.
    ///
    /// Handles both `\n` and `\r\n`: llama-server uses the former, and proxies
    /// in front of LM Studio have been seen to normalise to the latter.
    mutating func consume(_ bytes: some Sequence<UInt8>) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(byte)
            }
        }
        return lines
    }

    /// Whatever is left when the connection closes without a final newline.
    /// Servers do this; ignoring it loses the last token.
    mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line.isEmpty ? nil : line
    }
}

// MARK: - SSE event parsing

/// What one SSE line means to the caller.
enum ChatCompletionSSEEvent: Sendable, Equatable {
    case delta(String)
    case done

    /// Nothing to emit. The payload records whether the line was nonetheless a
    /// well-formed `data:` frame, which is how the client distinguishes "the
    /// model said nothing" from "this isn't an SSE stream at all".
    case ignored(wasDataFrame: Bool)
}

/// Parses one line of an OpenAI-compatible chat-completion stream.
///
/// Written to tolerate everything the three servers actually emit rather than
/// what the spec describes. Comment lines (`: ping`) keep proxies from timing
/// out; role-only first deltas carry no content; LM Studio's final usage chunk
/// has an empty `choices` array; and Ollama reports a missing model as a
/// `data:`-framed error object rather than an HTTP status, because the status
/// went out with the headers before it tried to load anything.
///
/// Tolerance stops at `{"error": …}`. Silently skipping that is how a client
/// ends up reporting an empty answer for what was really a hard failure.
enum ChatCompletionSSEParser {

    static func event(for line: String) throws -> ChatCompletionSSEEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Blank separator, comment/heartbeat, or a field we don't use
        // (`event:`, `id:`, `retry:`).
        guard trimmed.hasPrefix("data:") else {
            return .ignored(wasDataFrame: false)
        }

        let payload = trimmed
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { return .done }
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else {
            return .ignored(wasDataFrame: true)
        }

        // Errors first: an error envelope also decodes as a chunk with no
        // choices, so checking chunks first would swallow it.
        if let message = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).message {
            throw ModelServiceError.server(message: message)
        }

        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else {
            // Malformed JSON from a server that is otherwise streaming fine.
            // Dropping one frame beats aborting a whole answer.
            return .ignored(wasDataFrame: true)
        }

        guard let content = chunk.choices?.first?.delta?.content, !content.isEmpty else {
            return .ignored(wasDataFrame: true)
        }
        return .delta(content)
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    /// `{"error": {"message": "..."}}` on every server except Ollama, which
    /// sometimes sends `{"error": "model not found"}`. Both shapes have been
    /// observed, so both decode.
    private struct ErrorEnvelope: Decodable {
        let message: String?

        private enum CodingKeys: String, CodingKey { case error }
        private struct Detail: Decodable { let message: String? }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let detail = try? container.decode(Detail.self, forKey: .error) {
                message = detail.message
            } else {
                message = try container.decode(String.self, forKey: .error)
            }
        }
    }
}
