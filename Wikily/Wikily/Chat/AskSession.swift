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
                    self?.appendDelta(delta, to: answerID)
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

    private func appendDelta(_ delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += delta
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
