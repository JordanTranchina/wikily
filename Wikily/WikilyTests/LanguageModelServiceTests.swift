import Foundation
import Testing
@testable import Wikily

/// Backend-agnostic behaviour: the delta contract, availability reporting, and
/// the descriptor the settings picker persists.
struct LanguageModelServiceTests {

    // MARK: - Snapshot → delta

    @Test func cumulativeSnapshotsBecomeAppendOnlyDeltas() {
        // Exactly what Apple's ResponseStream hands back: the whole answer, again,
        // every tick.
        var deltas = CumulativeTextDeltas()
        let snapshots = ["The", "The rate", "The rate limit", "The rate limit is 100."]

        var emitted: [String] = []
        for snapshot in snapshots {
            if let delta = deltas.delta(for: snapshot) { emitted.append(delta) }
        }

        #expect(emitted == [ "The", " rate", " limit", " is 100."])
        #expect(emitted.joined() == snapshots.last)
        #expect(deltas.emitted == snapshots.last)
    }

    @Test func aRepeatedSnapshotProducesNothing() {
        var deltas = CumulativeTextDeltas()
        #expect(deltas.delta(for: "Hello") == "Hello")
        #expect(deltas.delta(for: "Hello") == nil)
        #expect(deltas.delta(for: "Hello") == nil)
    }

    @Test func theFirstSnapshotIsEmittedWhole() {
        var deltas = CumulativeTextDeltas()
        #expect(deltas.delta(for: "") == nil)
        #expect(deltas.delta(for: "Hello, world") == "Hello, world")
    }

    /// A backend that revises text it already emitted breaks the append-only
    /// contract no matter what we do. The longest-common-prefix rule at least
    /// keeps the changed tail rather than dropping it silently.
    @Test func aRevisedSnapshotStillYieldsItsChangedTail() {
        var deltas = CumulativeTextDeltas()
        #expect(deltas.delta(for: "The rate limit is 90") == "The rate limit is 90")
        #expect(deltas.delta(for: "The rate limit is 100/min") == "100/min")
        #expect(deltas.emitted == "The rate limit is 100/min")
    }

    @Test func aShorterSnapshotDoesNotResurrectOldText() {
        var deltas = CumulativeTextDeltas()
        _ = deltas.delta(for: "abcdef")
        #expect(deltas.delta(for: "abc") == nil)
        #expect(deltas.emitted == "abc")
    }

    @Test func multiByteCharactersAreNotSplitMidScalar() {
        var deltas = CumulativeTextDeltas()
        #expect(deltas.delta(for: "Résumé") == "Résumé")
        #expect(deltas.delta(for: "Résumé — 日本語") == " — 日本語")
        #expect(deltas.delta(for: "Résumé — 日本語 🎧") == " 🎧")
    }

    // MARK: - Availability reporting

    @Test func anAvailableBackendHasNoMessage() {
        #expect(ModelAvailability.available.isAvailable)
        #expect(ModelAvailability.available.message == nil)
    }

    @Test func anUnavailableBackendExplainsItselfInOneSentence() {
        let state = ModelAvailability.unavailable(
            reason: "Apple Intelligence is turned off.",
            recovery: "Turn it on in System Settings › Apple Intelligence & Siri."
        )
        #expect(!state.isAvailable)
        #expect(state.message == """
            Apple Intelligence is turned off. \
            Turn it on in System Settings › Apple Intelligence & Siri.
            """)
    }

    @Test func recoveryIsOptional() {
        let state = ModelAvailability.unavailable(reason: "Nothing is listening.")
        #expect(state.message == "Nothing is listening.")
    }

    // MARK: - Descriptors

    @Test func descriptorsSurviveAPersistenceRoundTrip() throws {
        let original = ModelDescriptor.localServer(
            baseURL: LocalServerKind.ollama.defaultBaseURL,
            modelID: "gemma3:4b",
            serverName: "Ollama"
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ModelDescriptor.self, from: data)
        #expect(restored == original)
        #expect(restored.id == original.id)
    }

    @Test func theAppleDescriptorIsAlwaysResolvable() throws {
        let service = try #require(ModelDescriptor.appleFoundation.makeService())
        #expect(service.descriptor.backend == .appleFoundation)
    }

    @Test func aLocalDescriptorResolvesToAClientForThatModel() throws {
        let descriptor = ModelDescriptor.localServer(
            baseURL: LocalServerKind.lmStudio.defaultBaseURL,
            modelID: "qwen2.5-7b-instruct",
            serverName: "LM Studio"
        )
        let service = try #require(descriptor.makeService())
        #expect(service.descriptor == descriptor)
    }

    /// A descriptor restored from a truncated preferences file. Returning nil
    /// rather than a half-configured client is what makes the settings UI fall
    /// back to the picker instead of failing mid-call.
    @Test func anIncompleteLocalDescriptorResolvesToNothing() {
        let noModel = ModelDescriptor(
            backend: .localServer,
            serverBaseURL: LocalServerKind.ollama.defaultBaseURL,
            modelID: nil,
            displayName: "?"
        )
        #expect(noModel.makeService() == nil)

        let noURL = ModelDescriptor(
            backend: .localServer,
            serverBaseURL: nil,
            modelID: "gemma3:4b",
            displayName: "?"
        )
        #expect(noURL.makeService() == nil)
    }

    // MARK: - Degrading when the server is gone

    @Test func aMissingServerReportsWhereItLookedAndWhatToStart() async throws {
        let baseURL = try #require(URL(string: "http://127.0.0.1:49714"))
        let service = LocalServerModelService(
            baseURL: baseURL,
            modelID: "gemma3:4b",
            session: LocalServerDiscovery.makeSession(timeout: 1)
        )

        let state = await service.availability()
        #expect(!state.isAvailable)
        let message = try #require(state.message)
        #expect(message.contains("127.0.0.1:49714"))
        #expect(!message.isEmpty)
    }

    @Test func generatingAgainstAMissingServerFailsFastRatherThanHanging() async {
        let service = LocalServerModelService(
            baseURL: URL(string: "http://127.0.0.1:49715")!,
            modelID: "gemma3:4b",
            session: LocalServerDiscovery.makeSession(timeout: 1)
        )

        let clock = ContinuousClock()
        var thrown: (any Error)?
        let elapsed = await clock.measure {
            do {
                for try await _ in service.stream(prompt: "hi", systemPrompt: nil) {}
            } catch {
                thrown = error
            }
        }

        #expect(thrown != nil, "a refused connection has to surface as an error")
        #expect(elapsed < .seconds(5), "stream took \(elapsed)")
    }

    // MARK: - Protocol defaults

    @Test func completeConcatenatesTheStream() async throws {
        let stub = StubModelService(deltas: ["The ", "rate ", "limit ", "is 100."])
        #expect(try await stub.complete(prompt: "?") == "The rate limit is 100.")
    }

    @Test func completePropagatesAMidStreamFailure() async {
        let stub = StubModelService(
            deltas: ["partial "],
            failure: ModelServiceError.server(message: "context length exceeded")
        )
        await #expect(throws: ModelServiceError.server(message: "context length exceeded")) {
            try await stub.complete(prompt: "?")
        }
    }
}

/// Minimal backend used to test the protocol's own behaviour without either real
/// one — the same seam a preview or a UI test would use.
private struct StubModelService: LanguageModelService {
    let descriptor = ModelDescriptor(backend: .localServer, displayName: "Stub")
    var deltas: [String] = []
    var failure: ModelServiceError?

    func availability() async -> ModelAvailability { .available }

    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        let deltas = self.deltas
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish(throwing: failure)
        }
    }
}
