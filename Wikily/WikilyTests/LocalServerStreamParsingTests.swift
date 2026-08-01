import Foundation
import Testing
@testable import Wikily

/// Covers the part of the local-server client that has no server in it.
///
/// SSE parsing is where these clients actually break, and none of the failures
/// need a network to reproduce: a line split across two reads, a `data:` frame
/// carrying an error instead of a token, a final chunk with an empty `choices`
/// array. All of it is exercised here against payloads captured from the three
/// servers, so the suite stays honest on a machine with nothing running.
struct LocalServerStreamParsingTests {

    // MARK: - Captured payloads

    /// An Ollama response, verbatim in shape: a role-only opening delta with
    /// empty content, three content deltas, a finish chunk with an empty delta,
    /// then `[DONE]`.
    static let ollamaStream = """
        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1730000000,\
        "model":"gemma3:4b","choices":[{"index":0,"delta":{"role":"assistant","content":""},\
        "finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1730000000,\
        "model":"gemma3:4b","choices":[{"index":0,"delta":{"content":"The rate"},\
        "finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1730000000,\
        "model":"gemma3:4b","choices":[{"index":0,"delta":{"content":" limit is"},\
        "finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1730000000,\
        "model":"gemma3:4b","choices":[{"index":0,"delta":{"content":" 100/min."},\
        "finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1730000000,\
        "model":"gemma3:4b","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """

    /// LM Studio, with the trailing usage-only chunk that carries no choices at
    /// all, and CRLF line endings.
    static let lmStudioStream = [
        #"data: {"id":"c","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"}}]}"#,
        "",
        #"data: {"id":"c","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"}}]}"#,
        "",
        #"data: {"id":"c","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" there"}}]}"#,
        "",
        #"data: {"id":"c","object":"chat.completion.chunk","choices":[],"usage":{"total_tokens":9}}"#,
        "",
        "data: [DONE]",
        "",
    ].joined(separator: "\r\n")

    /// llama-server, which interleaves SSE comment heartbeats and omits the
    /// final newline when the connection closes.
    static let llamaCppStream = """
        : ping

        data: {"choices":[{"delta":{"content":"one"}}]}

        : ping

        data: {"choices":[{"delta":{"content":" two"}}]}
        """

    /// Feed a whole payload through the accumulator and parser in fixed-size
    /// byte chunks, returning the concatenated deltas and whether `[DONE]` came.
    private static func drain(
        _ payload: String,
        chunkSize: Int
    ) throws -> (text: String, sawDone: Bool) {
        var accumulator = SSELineAccumulator()
        var text = ""
        var sawDone = false

        let bytes = Array(payload.utf8)
        var index = 0
        while index < bytes.count {
            let end = min(index + chunkSize, bytes.count)
            let lines = accumulator.consume(bytes[index..<end])
            for line in lines {
                switch try ChatCompletionSSEParser.event(for: line) {
                case .delta(let piece): text += piece
                case .done: sawDone = true
                case .ignored: break
                }
            }
            index = end
        }
        if let trailing = accumulator.flush() {
            if case .delta(let piece) = try ChatCompletionSSEParser.event(for: trailing) {
                text += piece
            }
        }
        return (text, sawDone)
    }

    // MARK: - Whole-stream behaviour

    @Test func parsesAnOllamaStream() throws {
        let result = try Self.drain(Self.ollamaStream, chunkSize: 4096)
        #expect(result.text == "The rate limit is 100/min.")
        #expect(result.sawDone)
    }

    @Test func parsesAnLMStudioStreamWithCRLFAndAUsageOnlyChunk() throws {
        let result = try Self.drain(Self.lmStudioStream, chunkSize: 4096)
        #expect(result.text == "Hello there")
        #expect(result.sawDone)
    }

    @Test func recoversTheLastTokenWhenTheStreamEndsWithoutANewline() throws {
        let result = try Self.drain(Self.llamaCppStream, chunkSize: 4096)
        #expect(result.text == "one two")
        #expect(!result.sawDone, "llama-server closed without [DONE]")
    }

    /// The regression that matters most: a read boundary is not a line boundary.
    /// Every split offset from one byte upward has to produce the same answer.
    @Test(arguments: [1, 2, 3, 5, 7, 13, 17, 64, 199])
    func splitPointsDoNotChangeTheResult(chunkSize: Int) throws {
        let ollama = try Self.drain(Self.ollamaStream, chunkSize: chunkSize)
        #expect(ollama.text == "The rate limit is 100/min.")
        #expect(ollama.sawDone)

        let lmStudio = try Self.drain(Self.lmStudioStream, chunkSize: chunkSize)
        #expect(lmStudio.text == "Hello there")

        let llamaCpp = try Self.drain(Self.llamaCppStream, chunkSize: chunkSize)
        #expect(llamaCpp.text == "one two")
    }

    // MARK: - Line accumulation

    @Test func holdsAPartialLineUntilItsNewlineArrives() {
        var accumulator = SSELineAccumulator()
        #expect(accumulator.consume(Array("data: {\"cho".utf8)).isEmpty)
        #expect(accumulator.consume(Array("ices\":[]}".utf8)).isEmpty)

        let lines = accumulator.consume(Array("\n".utf8))
        #expect(lines == ["data: {\"choices\":[]}"])
    }

    @Test func stripsCarriageReturnsButKeepsBlankSeparators() {
        var accumulator = SSELineAccumulator()
        let lines = accumulator.consume(Array("a\r\n\r\nb\n".utf8))
        #expect(lines == ["a", "", "b"])
    }

    @Test func flushIsEmptyWhenTheStreamEndedOnANewline() {
        var accumulator = SSELineAccumulator()
        _ = accumulator.consume(Array("data: [DONE]\n".utf8))
        #expect(accumulator.flush() == nil)
    }

    @Test func flushOnlyYieldsOnce() {
        var accumulator = SSELineAccumulator()
        _ = accumulator.consume(Array("tail".utf8))
        #expect(accumulator.flush() == "tail")
        #expect(accumulator.flush() == nil)
    }

    // MARK: - Single-line parsing

    @Test func recognisesTheTerminator() throws {
        #expect(try ChatCompletionSSEParser.event(for: "data: [DONE]") == .done)
        // Some servers omit the space after the colon.
        #expect(try ChatCompletionSSEParser.event(for: "data:[DONE]") == .done)
    }

    @Test func ignoresNonDataLines() throws {
        for line in ["", "   ", ": ping", "event: message", "id: 42", "retry: 3000"] {
            #expect(
                try ChatCompletionSSEParser.event(for: line) == .ignored(wasDataFrame: false),
                "\(line) should not look like a data frame"
            )
        }
    }

    @Test func ignoresDeltasWithNoContent() throws {
        // Role-only opening chunk.
        #expect(
            try ChatCompletionSSEParser.event(
                for: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
            ) == .ignored(wasDataFrame: true)
        )
        // Explicit empty string.
        #expect(
            try ChatCompletionSSEParser.event(
                for: #"data: {"choices":[{"delta":{"content":""}}]}"#
            ) == .ignored(wasDataFrame: true)
        )
        // Null content.
        #expect(
            try ChatCompletionSSEParser.event(
                for: #"data: {"choices":[{"delta":{"content":null}}]}"#
            ) == .ignored(wasDataFrame: true)
        )
        // Usage-only final chunk with no choices at all.
        #expect(
            try ChatCompletionSSEParser.event(
                for: #"data: {"choices":[],"usage":{"total_tokens":9}}"#
            ) == .ignored(wasDataFrame: true)
        )
    }

    @Test func skipsMalformedJSONRatherThanAbortingTheAnswer() throws {
        for payload in ["data: {not json", "data: {\"choices\":", "data: null", "data: 12"] {
            #expect(
                try ChatCompletionSSEParser.event(for: payload) == .ignored(wasDataFrame: true),
                "\(payload) should be skipped, not fatal"
            )
        }
    }

    @Test func preservesWhitespaceInsideDeltas() throws {
        // The line is trimmed; the decoded content must not be.
        let event = try ChatCompletionSSEParser.event(
            for: #"data: {"choices":[{"delta":{"content":"  spaced  "}}]}"#
        )
        #expect(event == .delta("  spaced  "))
    }

    @Test func surfacesAnObjectShapedErrorEnvelope() {
        #expect(throws: ModelServiceError.server(message: "model 'ghost' not found")) {
            try ChatCompletionSSEParser.event(
                for: #"data: {"error":{"message":"model 'ghost' not found","type":"api_error"}}"#
            )
        }
    }

    /// Ollama has been seen to send the bare-string form.
    @Test func surfacesAStringShapedErrorEnvelope() {
        #expect(throws: ModelServiceError.server(message: "model not found")) {
            try ChatCompletionSSEParser.event(for: #"data: {"error":"model not found"}"#)
        }
    }

    @Test func anErrorEnvelopeIsNotMistakenForAnEmptyChunk() throws {
        // It decodes cleanly as a chunk with no `choices`, so ordering inside the
        // parser is what keeps this from being silently swallowed.
        var thrown: (any Error)?
        do {
            _ = try ChatCompletionSSEParser.event(
                for: #"data: {"error":{"message":"context length exceeded"}}"#
            )
        } catch {
            thrown = error
        }
        let error = try #require(thrown as? ModelServiceError)
        #expect(error.errorDescription == "context length exceeded")
    }

    // MARK: - URL construction

    @Test(arguments: [
        "http://127.0.0.1:11434",
        "http://127.0.0.1:11434/",
        "http://127.0.0.1:11434/v1",
        "http://127.0.0.1:11434/v1/",
    ])
    func buildsTheSameEndpointsFromEveryBaseURLShape(raw: String) throws {
        let baseURL = try #require(URL(string: raw))
        #expect(
            LocalServerEndpoints.models(baseURL: baseURL).absoluteString
                == "http://127.0.0.1:11434/v1/models"
        )
        #expect(
            LocalServerEndpoints.chatCompletions(baseURL: baseURL).absoluteString
                == "http://127.0.0.1:11434/v1/chat/completions"
        )
    }

    /// A base URL behind a reverse proxy keeps its prefix.
    ///
    /// This test and the one above exist because the first implementation of
    /// `versioned(baseURL:path:)` normalised by repeatedly deleting the last
    /// path component, which spins forever on a root path — the suite hung at
    /// 100% CPU rather than failing, which is exactly how that class of bug
    /// reaches users.
    @Test func preservesAPathPrefixWhenAppendingTheAPIVersion() throws {
        let baseURL = try #require(URL(string: "http://127.0.0.1:8080/llm/"))
        #expect(
            LocalServerEndpoints.chatCompletions(baseURL: baseURL).absoluteString
                == "http://127.0.0.1:8080/llm/v1/chat/completions"
        )
    }

    // MARK: - Request construction

    @Test func buildsAStreamingChatRequestWithTheSystemPromptFirst() throws {
        let service = LocalServerModelService(
            baseURL: LocalServerKind.ollama.defaultBaseURL,
            modelID: "gemma3:4b"
        )
        let request = try service.makeChatRequest(
            prompt: "What is the rate limit?",
            systemPrompt: "Answer only from the provided wiki page."
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        #expect(decoded.model == "gemma3:4b")
        #expect(decoded.stream)
        #expect(decoded.messages == [
            ChatMessage(role: "system", content: "Answer only from the provided wiki page."),
            ChatMessage(role: "user", content: "What is the rate limit?"),
        ])
    }

    @Test func omitsTheSystemMessageWhenThereIsNoSystemPrompt() throws {
        let service = LocalServerModelService(
            baseURL: LocalServerKind.lmStudio.defaultBaseURL,
            modelID: "qwen2.5-7b-instruct"
        )
        for systemPrompt in [nil, ""] as [String?] {
            let request = try service.makeChatRequest(prompt: "Hi", systemPrompt: systemPrompt)
            let body = try #require(request.httpBody)
            let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
            #expect(decoded.messages == [ChatMessage(role: "user", content: "Hi")])
        }
    }
}
