import Foundation
import Testing
@testable import Wikily

/// The pure mapping from `CallSession` state to the toolbar's five-state status
/// icon. No window, no panel, no audio — just the priority rules.
@MainActor
struct OverlayStatusTests {

    private static var sampleVaultPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
    }

    private struct StubService: LanguageModelService {
        var descriptor = ModelDescriptor(
            backend: .appleFoundation,
            serverBaseURL: nil,
            modelID: nil,
            displayName: "Stub"
        )

        func availability() async -> ModelAvailability { .available }

        func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
            // Never finishes within the test body, so `isAnswering` stays true
            // for the duration of the assertion — these tests only care about
            // the state while a request is in flight.
            AsyncThrowingStream { _ in }
        }
    }

    @Test func freshSessionIsIdle() {
        let session = CallSession()
        #expect(OverlayStatus(session: session) == .idle)
    }

    @Test func listeningWithNothingMatchedShowsListening() {
        let session = CallSession()
        session.enterPreviewListening()
        #expect(OverlayStatus(session: session) == .listening)
    }

    @Test func aMatchedPageShowsReady() async {
        let session = CallSession()
        await session.loadWiki(directory: Self.sampleVaultPath)
        session.enterPreviewListening()
        session.ingest(TranscriptSegment(
            text: "I wanted an update on the Becky promotion.",
            source: .system,
            startTime: 0
        ))
        #expect(session.currentMatch != nil)
        #expect(OverlayStatus(session: session) == .ready)
    }

    @Test func aFreeFormAskInFlightShowsThinking() {
        let session = CallSession()
        session.askSession.ask(
            "What's the status?",
            page: nil,
            transcript: [TranscriptSegment(text: "hi", source: .system, startTime: 0)],
            service: StubService()
        )
        defer { session.askSession.cancel() }
        #expect(OverlayStatus(session: session) == .thinking)
    }

    @Test func aResearchActionInFlightShowsResearching() {
        let session = CallSession()
        session.askSession.run(
            .research,
            page: nil,
            transcript: [TranscriptSegment(text: "hi", source: .system, startTime: 0)],
            service: StubService()
        )
        defer { session.askSession.cancel() }
        #expect(OverlayStatus(session: session) == .researching)
    }

    /// An in-flight ask outranks a matched page — the icon must show what's
    /// happening right now, not what was found before the question was asked.
    @Test func anInFlightAskOutranksAMatchedPage() async {
        let session = CallSession()
        await session.loadWiki(directory: Self.sampleVaultPath)
        session.enterPreviewListening()
        session.ingest(TranscriptSegment(
            text: "I wanted an update on the Becky promotion.",
            source: .system,
            startTime: 0
        ))
        #expect(session.currentMatch != nil)

        session.askSession.run(
            .research,
            page: session.currentMatch?.document,
            transcript: session.transcript,
            service: StubService()
        )
        defer { session.askSession.cancel() }
        #expect(OverlayStatus(session: session) == .researching)
    }
}
