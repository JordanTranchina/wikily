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
