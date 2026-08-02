import Foundation
import OSLog

/// The Q&A thread shown on the HUD card.
///
/// Separate from `CallSession` because the two have genuinely different
/// lifetimes: the call runs for an hour, a question and its answer last seconds,
/// and the user can clear the thread without touching the call. Keeping them
/// apart also means the whole ask flow is testable against a stub model service
/// with no audio stack involved.
@MainActor
@Observable
final class AskSession {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "AskSession")

    struct Message: Identifiable, Equatable, Sendable {
        enum Role: Sendable { case user, assistant }

        let id = UUID()
        var role: Role
        var text: String

        static func == (lhs: Message, rhs: Message) -> Bool {
            lhs.id == rhs.id && lhs.role == rhs.role && lhs.text == rhs.text
        }
    }

    // MARK: - Published state

    private(set) var messages: [Message] = []
    private(set) var isAnswering = false
    private(set) var errorMessage: String?

    /// Bound to the text field. Owned here so clearing on send is one place.
    var draft: String = ""

    /// The thread is a live aid, not a transcript — old turns are dropped rather
    /// than scrolled, so the card never grows without bound during a long call.
    static let messageLimit = 20

    /// Hard ceiling on one answer's length, independent of whatever cap the
    /// backend was asked to honour. Both backends are told to stop generating
    /// well before this — see `AppleFoundationModelService.maximumResponseTokens`
    /// and `ChatCompletionRequest.maxTokens` — but a request-side limit is the
    /// backend's word, not a guarantee, and a degenerate loop that ignores it is
    /// exactly the failure this exists to catch regardless of backend or prompt.
    static let maximumAnswerCharacters = 4_000

    private var task: Task<Void, Never>?

    var canSend: Bool {
        !draft.trimmed.isEmpty && !isAnswering
    }

    // MARK: - Asking

    /// Send the draft.
    func sendDraft(
        page: WikiDocument?,
        transcript: [TranscriptSegment],
        service: some LanguageModelService
    ) {
        let question = draft.trimmed
        guard !question.isEmpty else { return }
        draft = ""
        ask(question, page: page, transcript: transcript, service: service)
    }

    func run(
        _ action: QuickAction,
        page: WikiDocument?,
        transcript: [TranscriptSegment],
        service: some LanguageModelService
    ) {
        ask(action.prompt, displayAs: action.title, page: page, transcript: transcript, service: service)
    }

    /// Ask a question and stream the answer into the thread.
    ///
    /// - Parameter displayAs: what to show as the user's turn, when the prompt
    ///   actually sent is more verbose than what the user clicked. Showing the
    ///   full internal prompt back to them would be noise.
    func ask(
        _ question: String,
        displayAs displayText: String? = nil,
        page: WikiDocument?,
        transcript: [TranscriptSegment],
        service: some LanguageModelService
    ) {
        // A second question supersedes the first. Mid-call, the previous answer
        // has already stopped being what the user wants.
        task?.cancel()
        errorMessage = nil

        append(Message(role: .user, text: displayText ?? question))

        // No page and nothing transcribed is not a question a model can answer —
        // it is a request to describe nothing. The system prompt already tells
        // the model to say so itself, but that is a request, not a guarantee:
        // asked to "recap the call" with no call to recap, the on-device model
        // was observed spinning out the same invented bullet point hundreds of
        // times rather than admitting it had nothing to recap. Answering it here
        // costs nothing, is never wrong, and removes the failure mode entirely
        // rather than hoping the prompt is obeyed.
        guard page != nil || !transcript.isEmpty else {
            append(Message(
                role: .assistant,
                text: "Nothing to go on yet — no page has matched and nothing has been "
                    + "transcribed. Start listening, or open a page first."
            ))
            return
        }

        let answerID = append(Message(role: .assistant, text: ""))
        isAnswering = true

        let prompt = GroundedPrompt.build(
            question: question,
            page: page,
            transcript: transcript
        )

        task = Task { [weak self] in
            do {
                for try await delta in service.stream(
                    prompt: prompt.user,
                    systemPrompt: prompt.system
                ) {
                    if Task.isCancelled { return }
                    guard let self, self.appendDelta(delta, to: answerID) else {
                        // Either the session went away, or the answer hit the
                        // runaway-length ceiling — either way, stop pulling more
                        // tokens through a stream nothing will read further.
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.failAnswer(answerID, with: error)
                return
            }
            self?.finishAnswer(answerID)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isAnswering = false
    }

    func clear() {
        cancel()
        messages.removeAll()
        errorMessage = nil
        draft = ""
    }

    // MARK: - Internals

    @discardableResult
    private func append(_ message: Message) -> UUID {
        messages.append(message)
        if messages.count > Self.messageLimit {
            messages.removeFirst(messages.count - Self.messageLimit)
        }
        return message.id
    }

    /// Appends one delta, returning whether the caller should keep pulling more.
    /// `false` means either the message is gone (session cleared mid-stream) or
    /// the answer just crossed `maximumAnswerCharacters` and generation should
    /// stop — see the constant's doc for why that ceiling exists at all.
    private func appendDelta(_ delta: String, to id: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return false }
        messages[index].text += delta

        guard messages[index].text.count > Self.maximumAnswerCharacters else { return true }
        messages[index].text = String(messages[index].text.prefix(Self.maximumAnswerCharacters))
            + "…\n\n[Stopped — this answer was running far longer than expected.]"
        isAnswering = false
        return false
    }

    private func finishAnswer(_ id: UUID) {
        isAnswering = false
        // An empty answer is a failure the user can otherwise only read as the
        // app having ignored them.
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].text.trimmed.isEmpty
        else { return }
        messages[index].text = "No answer came back. The model may not be available."
    }

    private func failAnswer(_ id: UUID, with error: Error) {
        isAnswering = false
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = message
        logger.error("Ask failed: \(message, privacy: .public)")

        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].text.trimmed.isEmpty {
            // Replace the empty bubble rather than leaving it blank next to a
            // separate error line.
            messages.remove(at: index)
        }
    }
}
