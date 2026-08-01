import Foundation
import Testing
@testable import Wikily

/// Discovery has two jobs and both are tested here without a server: decode a
/// `/v1/models` body, and fail fast when nothing answers.
///
/// The second is the one that matters at launch. Discovery runs in front of a UI
/// that must not wait for it, so the assertions below are about *time*, not just
/// results — a probe that eventually returns the right answer after thirty
/// seconds is still a bug.
struct LocalServerDiscoveryTests {

    /// A loopback port nothing should be listening on. Even if something is, the
    /// assertions still hold: the test only requires that it is not serving a
    /// decodable OpenAI-style model list.
    private let deadPort = 49_713

    private var deadURL: URL {
        URL(string: "http://127.0.0.1:\(deadPort)")!
    }

    // MARK: - Model list decoding

    @Test func decodesAnOllamaModelList() throws {
        let payload = Data("""
            {"object":"list","data":[
              {"id":"gemma3:4b","object":"model","created":1730000000,"owned_by":"library"},
              {"id":"qwen2.5:7b","object":"model","created":1730000001,"owned_by":"library"}
            ]}
            """.utf8)
        #expect(try LocalServerDiscovery.parseModelList(payload) == ["gemma3:4b", "qwen2.5:7b"])
    }

    @Test func decodesAnLMStudioModelList() throws {
        let payload = Data("""
            {"object":"list","data":[
              {"id":"qwen2.5-7b-instruct","object":"model","owned_by":"organization_owner"},
              {"id":"text-embedding-nomic-embed-text-v1.5","object":"model",
               "owned_by":"organization_owner"}
            ]}
            """.utf8)
        // Embedding models are returned unfiltered on purpose: `/v1/models` gives
        // no reliable way to tell them apart across the three servers, and
        // guessing from the name would hide legitimately-named chat models.
        #expect(try LocalServerDiscovery.parseModelList(payload).count == 2)
    }

    @Test func decodesALlamaServerModelList() throws {
        // llama-server reports the single loaded GGUF, sometimes by file path.
        let payload = Data("""
            {"object":"list","data":[
              {"id":"/models/gemma-3-4b-it-Q4_K_M.gguf","object":"model","created":0,
               "owned_by":"llamacpp"}
            ]}
            """.utf8)
        #expect(
            try LocalServerDiscovery.parseModelList(payload)
                == ["/models/gemma-3-4b-it-Q4_K_M.gguf"]
        )
    }

    @Test func keepsTheServersOwnOrdering() throws {
        // Ollama returns most-recently-used first; re-sorting would bury the
        // model the user actually wants under an alphabetical accident.
        let payload = Data(#"{"object":"list","data":[{"id":"z"},{"id":"a"},{"id":"m"}]}"#.utf8)
        #expect(try LocalServerDiscovery.parseModelList(payload) == ["z", "a", "m"])
    }

    @Test func dropsEntriesWithNoUsableIDButKeepsTheRest() throws {
        let payload = Data(#"{"data":[{"id":"good"},{"object":"model"},{"id":""}]}"#.utf8)
        #expect(try LocalServerDiscovery.parseModelList(payload) == ["good"])
    }

    @Test func anEmptyListDecodesRatherThanThrowing() throws {
        // A running server with no models pulled is a real state, and the picker
        // should say "no models" rather than "server not found".
        #expect(try LocalServerDiscovery.parseModelList(Data(#"{"data":[]}"#.utf8)).isEmpty)
    }

    @Test(arguments: [
        "",
        "not json",
        "<html><title>404</title></html>",
        #"{"models":["gemma3:4b"]}"#,   // Ollama's *native* API shape, not /v1
        #"{"data":"nope"}"#,
    ])
    func rejectsBodiesThatArentAModelList(body: String) {
        // This is what stops something else squatting on :8080 from showing up
        // in the picker as a model server.
        #expect(throws: (any Error).self) {
            try LocalServerDiscovery.parseModelList(Data(body.utf8))
        }
    }

    // MARK: - Kinds

    @Test func wellKnownPortsMapToTheirServers() throws {
        #expect(LocalServerKind.ollama.port == 11434)
        #expect(LocalServerKind.lmStudio.port == 1234)
        #expect(LocalServerKind.llamaCpp.port == 8080)

        let fromURL = try #require(URL(string: "http://127.0.0.1:1234"))
        #expect(LocalServerKind(baseURL: fromURL) == .lmStudio)
    }

    @Test func anUnknownPortHasNoKind() throws {
        let url = try #require(URL(string: "http://127.0.0.1:\(deadPort)"))
        #expect(LocalServerKind(baseURL: url) == nil)

        // ...and an endpoint on one still labels itself usefully.
        let endpoint = LocalServerEndpoint(kind: nil, baseURL: url, models: ["m"])
        #expect(endpoint.displayName == "127.0.0.1:\(deadPort)")
    }

    @Test func loopbackIsAddressedByLiteralIPNotLocalhost() {
        // Resolving `localhost` can try ::1 first and burn the probe budget on a
        // failed connection before falling back to IPv4.
        for kind in LocalServerKind.allCases {
            #expect(kind.defaultBaseURL.host == "127.0.0.1")
        }
    }

    @Test func endpointsExpandIntoOnePickerRowPerModel() {
        let endpoint = LocalServerEndpoint(
            kind: .ollama,
            baseURL: LocalServerKind.ollama.defaultBaseURL,
            models: ["gemma3:4b", "qwen2.5:7b"]
        )
        let rows = endpoint.descriptors
        #expect(rows.count == 2)
        #expect(rows[0].modelID == "gemma3:4b")
        #expect(rows[0].displayName == "gemma3:4b — Ollama")
        #expect(rows[0].backend == .localServer)
        // Distinct, stable identity is what lets the choice survive a restart.
        #expect(rows[0].id != rows[1].id)
        #expect(rows[0].id == "local:http://127.0.0.1:11434:gemma3:4b")
    }

    // MARK: - Nothing listening

    @Test func probingADeadPortReturnsNilQuickly() async {
        let clock = ContinuousClock()
        var result: LocalServerEndpoint?
        let elapsed = await clock.measure {
            result = await LocalServerDiscovery.probe(baseURL: deadURL, timeout: 1)
        }

        #expect(result == nil)
        // A refused loopback connection comes back in microseconds; the bound is
        // loose enough for a loaded CI box and still catches a hang.
        #expect(elapsed < .seconds(3), "probe took \(elapsed)")
    }

    /// The launch-path guarantee: three probes, in parallel, bounded.
    ///
    /// Deliberately asserts on duration rather than on an empty result — this
    /// suite also runs on developer machines where Ollama genuinely *is*
    /// listening, and a test that failed there would just get deleted.
    @Test func probingEveryPortIsBoundedEvenWhenNothingIsRunning() async {
        let clock = ContinuousClock()
        var found: [LocalServerEndpoint] = []
        let elapsed = await clock.measure {
            found = await LocalServerDiscovery.probeAll(timeout: 1)
        }

        // Serial probes would cost 3x the timeout; parallel ones cost 1x.
        #expect(elapsed < .seconds(4), "probeAll took \(elapsed)")
        #expect(found.count <= LocalServerKind.allCases.count)
        #expect(Set(found.map(\.id)).count == found.count, "duplicate endpoints")
    }

    @Test func probeAllOrdersResultsByServerNotByWhoAnsweredFirst() async {
        let found = await LocalServerDiscovery.probeAll(timeout: 1)
        let expectedOrder = LocalServerKind.allCases
        let actual = found.compactMap(\.kind)
        let positions = actual.compactMap { expectedOrder.firstIndex(of: $0) }
        #expect(positions == positions.sorted())
    }

    // MARK: - Live server (skipped when nothing is running)

    /// Exercises the real HTTP path end to end, and does nothing at all when no
    /// server is listening — which is the normal case in CI. It reports no
    /// failure and no skip marker when it no-ops; check the assertion count if
    /// you want to know whether it actually ran.
    @Test func liveServerRoundTripWhenOneHappensToBeRunning() async throws {
        let servers = await LocalServerDiscovery.probeAll(timeout: 1)
        guard let server = servers.first(where: { !$0.models.isEmpty }) else { return }

        let session = LocalServerDiscovery.makeSession(timeout: 5)
        let models = try await LocalServerDiscovery.models(at: server.baseURL, session: session)
        #expect(models == server.models)

        let service = LocalServerModelService(
            baseURL: server.baseURL,
            modelID: try #require(server.models.first)
        )
        #expect(await service.availability().isAvailable)
    }
}
