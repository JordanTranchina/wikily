import Foundation
import Testing
@testable import Wikily

/// Drives the ask flow against a stub model service — no Apple Intelligence, no
/// server, no audio.
@MainActor
struct AskSessionTests {

    /// A `LanguageModelService` that emits a scripted sequence, or fails.
    struct StubService: LanguageModelService {
        var descriptor = ModelDescriptor(
            backend: .appleFoundation,
            serverBaseURL: nil,
            modelID: nil,
            displayName: "Stub"
        )
        var deltas: [String] = []
        var failure: Error?
        /// Captures what the session actually sent, so grounding can be asserted.
        var recorder: PromptRecorder?

        func availability() async -> ModelAvailability { .available }

        func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
            recorder?.record(prompt: prompt, systemPrompt: systemPrompt)
            let deltas = deltas
            let failure = failure
            return AsyncThrowingStream { continuation in
                if let failure {
                    continuation.finish(throwing: failure)
                    return
                }
                for delta in deltas { continuation.yield(delta) }
                continuation.finish()
            }
        }
    }

    final class PromptRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _prompt: String?
        private var _systemPrompt: String?

        func record(prompt: String, systemPrompt: String?) {
            lock.lock(); defer { lock.unlock() }
            _prompt = prompt
            _systemPrompt = systemPrompt
        }

        var prompt: String? { lock.lock(); defer { lock.unlock() }; return _prompt }
        var systemPrompt: String? { lock.lock(); defer { lock.unlock() }; return _systemPrompt }
    }

    struct DummyError: LocalizedError {
        var errorDescription: String? { "the model is not available"; }
    }

    private func settle() async {
        // Let the streaming task run; the stub finishes immediately.
        for _ in 0..<20 { await Task.yield() }
    }

    private var page: WikiDocument {
        WikiDocument(
            id: "/wiki/becky.md",
            title: "Becky Promotion Campaign",
            summary: "Marketing push.",
            status: "In Progress",
            latestUpdate: nil,
            blocker: nil,
            tags: [],
            aliases: [],
            links: [],
            headings: [],
            body: "Body."
        )
    }

    // MARK: - Basics

    @Test func streamsAnAnswerIntoTheThread() async {
        let session = AskSession()
        session.ask(
            "What's the status?",
            page: page,
            transcript: [],
            service: StubService(deltas: ["In ", "progress", "."])
        )
        await settle()

        #expect(session.messages.count == 2)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[1].role == .assistant)
        #expect(session.messages[1].text == "In progress.")
        #expect(!session.isAnswering)
    }

    @Test func sendingClearsTheDraftImmediately() async {
        let session = AskSession()
        session.draft = "  what should I say?  "
        session.sendDraft(page: page, transcript: [], service: StubService(deltas: ["Say this."]))

        // Cleared synchronously — a draft still sitting in the field after Return
        // reads as the send having failed.
        #expect(session.draft.isEmpty)
        await settle()
        #expect(session.messages.first?.text == "what should I say?")
    }

    @Test func emptyOrWhitespaceDraftsAreNotSent() async {
        let session = AskSession()
        session.draft = "   "
        #expect(!session.canSend)
        session.sendDraft(page: page, transcript: [], service: StubService(deltas: ["x"]))
        await settle()
        #expect(session.messages.isEmpty)
    }

    // MARK: - Nothing to go on

    /// The bug that prompted this guard: Recap, clicked with no page matched and
    /// nothing transcribed, sent "recap the call so far" to a model with nothing
    /// to recap — and the on-device model responded by inventing a bullet point
    /// and repeating it hundreds of times rather than saying so. This is the
    /// client-side fix: don't ask at all when there is genuinely nothing to ask
    /// about.
    @Test func askingWithNoPageAndNoTranscriptNeverCallsTheModel() async {
        let recorder = PromptRecorder()
        let session = AskSession()
        session.ask(
            "Recap the call so far in a few bullet points.",
            displayAs: "Recap",
            page: nil,
            transcript: [],
            service: StubService(deltas: ["should never be read"], recorder: recorder)
        )
        await settle()

        #expect(recorder.prompt == nil, "the model must never be called with nothing to ground on")
        #expect(!session.isAnswering)
        #expect(session.messages.count == 2)
        #expect(session.messages[0].text == "Recap")
        #expect(session.messages[1].role == .assistant)
        #expect(session.messages[1].text.contains("Nothing to go on"))
    }

    /// A transcript with no matched page is real context (e.g. small talk before
    /// anything triggers a match) — the guard must not block on that alone.
    @Test func askingWithATranscriptButNoPageStillCallsTheModel() async {
        let recorder = PromptRecorder()
        let session = AskSession()
        session.ask(
            "What should I say next?",
            page: nil,
            transcript: [
                TranscriptSegment(text: "Hey, thanks for hopping on.", source: .microphone, startTime: 0)
            ],
            service: StubService(deltas: ["Go ahead."], recorder: recorder)
        )
        await settle()

        #expect(recorder.prompt != nil)
        #expect(session.messages.last?.text == "Go ahead.")
    }

    // MARK: - Runaway generation

    /// The second line of defense for the same bug: even if a future prompt or
    /// backend produces a degenerate loop with real context available, the
    /// answer cannot grow without bound.
    @Test func aRunawayAnswerIsCutOffRatherThanGrowingForever() async {
        let session = AskSession()
        let hugeDeltas = Array(repeating: "The caller has not yet asked for a refund.\n", count: 400)
        session.ask(
            "Recap the call so far.",
            page: page,
            transcript: [TranscriptSegment(text: "hi", source: .system, startTime: 0)],
            service: StubService(deltas: hugeDeltas)
        )
        // 400 buffered deltas take more pump cycles to drain than `settle()`
        // gives — a fixed budget rather than an unbounded poll, so a real
        // regression (the ceiling not firing) fails the test instead of hanging.
        for _ in 0..<2_000 where session.isAnswering {
            await Task.yield()
        }

        let answer = session.messages.last
        #expect(answer?.role == .assistant)
        #expect((answer?.text.count ?? 0) <= AskSession.maximumAnswerCharacters + 200)
        #expect(answer?.text.contains("Stopped") == true)
        #expect(!session.isAnswering)
    }

    // MARK: - Grounding

    @Test func theSentPromptIsGroundedInThePageAndTheCall() async {
        let recorder = PromptRecorder()
        let session = AskSession()
        session.ask(
            "What should I say?",
            page: page,
            transcript: [
                TranscriptSegment(text: "Any update on Becky?", source: .system, startTime: 0)
            ],
            service: StubService(deltas: ["ok"], recorder: recorder)
        )
        await settle()

        let prompt = recorder.prompt ?? ""
        #expect(prompt.contains("Becky Promotion Campaign"))
        #expect(prompt.contains("Them: Any update on Becky?"))
        #expect(recorder.systemPrompt == GroundedPrompt.systemPrompt)
    }

    @Test func quickActionsShowTheirLabelButSendTheFullerPrompt() async {
        let recorder = PromptRecorder()
        let session = AskSession()
        session.run(
            .whatToSay,
            page: page,
            transcript: [],
            service: StubService(deltas: ["ok"], recorder: recorder)
        )
        await settle()

        // The thread shows what the user clicked, not the internal wording.
        #expect(session.messages.first?.text == "What should I say?")
        #expect(recorder.prompt?.contains(QuickAction.whatToSay.prompt) == true)
    }

    // MARK: - Failure handling

    @Test func aFailedAnswerSurfacesTheReasonAndLeavesNoEmptyBubble() async {
        let session = AskSession()
        session.ask(
            "What's the status?",
            page: page,
            transcript: [],
            service: StubService(failure: DummyError())
        )
        await settle()

        #expect(session.errorMessage == "the model is not available")
        #expect(!session.isAnswering)
        // The empty assistant bubble is removed rather than left blank beside
        // the error line.
        #expect(session.messages.allSatisfy { $0.role == .user })
    }

    @Test func anEmptyAnswerIsReportedRatherThanLookingIgnored() async {
        let session = AskSession()
        session.ask("Anything?", page: page, transcript: [], service: StubService(deltas: []))
        await settle()

        let answer = session.messages.last
        #expect(answer?.role == .assistant)
        #expect(answer?.text.contains("No answer came back") == true)
    }

    // MARK: - Thread management

    @Test func askingAgainSupersedesTheAnswerInFlight() async {
        let session = AskSession()
        session.ask("First?", page: page, transcript: [], service: StubService(deltas: ["a"]))
        session.ask("Second?", page: page, transcript: [], service: StubService(deltas: ["b"]))
        await settle()

        #expect(session.messages.contains { $0.text == "Second?" })
        #expect(!session.isAnswering)
    }

    @Test func theThreadIsCappedSoTheCardCannotGrowWithoutBound() async {
        let session = AskSession()
        for index in 0..<AskSession.messageLimit {
            session.ask("q\(index)", page: page, transcript: [], service: StubService(deltas: ["a"]))
            await settle()
        }
        #expect(session.messages.count <= AskSession.messageLimit)
    }

    @Test func clearResetsEverything() async {
        let session = AskSession()
        session.ask("Anything?", page: page, transcript: [], service: StubService(deltas: ["a"]))
        await settle()
        session.draft = "leftover"
        session.clear()

        #expect(session.messages.isEmpty)
        #expect(session.draft.isEmpty)
        #expect(session.errorMessage == nil)
        #expect(!session.isAnswering)
    }
}
