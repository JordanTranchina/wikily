import Foundation
import Testing
@testable import Wikily

/// The prompt is the difference between this feature being useful and being
/// dangerous: the user reads the answer aloud to a customer within seconds of
/// seeing it. These assert the properties that keep a small on-device model from
/// confidently inventing a status, date or commitment.
struct GroundedPromptTests {

    private func page(
        title: String = "Project: Becky Promotion Campaign",
        status: String? = "In Progress (Deployment phase)",
        latestUpdate: String? = "Visual assets approved yesterday.",
        blocker: String? = "None",
        summary: String = "Marketing push for the Becky product line.",
        body: String = "Full page body about the campaign."
    ) -> WikiDocument {
        WikiDocument(
            id: "/wiki/becky.md",
            title: title,
            summary: summary,
            status: status,
            latestUpdate: latestUpdate,
            blocker: blocker,
            tags: ["marketing"],
            aliases: ["Becky promotion"],
            links: [],
            headings: [],
            body: body
        )
    }

    private func transcript(_ lines: [(String, AudioChunk.Source)]) -> [TranscriptSegment] {
        lines.enumerated().map { index, line in
            TranscriptSegment(text: line.0, source: line.1, startTime: Double(index) * 5)
        }
    }

    // MARK: - Grounding rules

    @Test func systemPromptForbidsOutsideKnowledgeAndInvention() {
        let system = GroundedPrompt.systemPrompt.lowercased()
        #expect(system.contains("only"))
        #expect(system.contains("do not guess"))
        #expect(system.contains("never invent"))
        // "I don't know" must be named as acceptable, or the model fills the gap.
        #expect(system.contains("not a failure"))
    }

    @Test func systemPromptDistinguishesSilenceFromDenial() {
        // Found by running the real model, not by reading the prompt. Asked
        // something the page didn't mention, it answered "we did not agree a
        // discount percentage" — asserting a fact from an absence. The user
        // would have read that to a customer as though the wiki said it.
        let system = GroundedPrompt.systemPrompt.lowercased()
        #expect(system.contains("silence is not denial"))
        #expect(system.contains("doesn't say"))
    }

    @Test func systemPromptRulesOutMarkupAndDialogueScripts() {
        // Both observed live: the model emitted **bold** (which a plain Text view
        // renders as literal asterisks) and, when asked for "the exact words",
        // scripted both sides of the call instead of giving one reply.
        let system = GroundedPrompt.systemPrompt.lowercased()
        #expect(system.contains("no markdown"))
        #expect(system.contains("dialogue"))
    }

    @Test func includesTheMatchedPagesStructuredFieldsInFull() {
        let prompt = GroundedPrompt.build(question: "What's the status?", page: page(), transcript: [])
        #expect(prompt.user.contains("Project: Becky Promotion Campaign"))
        #expect(prompt.user.contains("In Progress (Deployment phase)"))
        #expect(prompt.user.contains("Visual assets approved yesterday."))
        #expect(prompt.user.contains("Blocker: None"))
    }

    @Test func statesPlainlyWhenNoPageMatched() {
        // Omitting the section entirely makes the model assume a page was given.
        let prompt = GroundedPrompt.build(question: "What's the status?", page: nil, transcript: [])
        #expect(prompt.user.contains("No wiki page matched"))
    }

    @Test func includesRecentCallWithSpeakerLabels() {
        let prompt = GroundedPrompt.build(
            question: "What should I say?",
            page: page(),
            transcript: transcript([
                ("Where did the promotion land?", .system),
                ("Let me check on that.", .microphone),
            ])
        )
        #expect(prompt.user.contains("Them: Where did the promotion land?"))
        #expect(prompt.user.contains("You: Let me check on that."))
    }

    @Test func statesPlainlyWhenNothingHasBeenSaidYet() {
        let prompt = GroundedPrompt.build(question: "Recap", page: page(), transcript: [])
        #expect(prompt.user.contains("Nothing has been transcribed yet"))
    }

    @Test func keepsOnlyTheMostRecentTurns() {
        let lines = (0..<30).map { ("line number \($0)", AudioChunk.Source.system) }
        let prompt = GroundedPrompt.build(
            question: "Recap",
            page: page(),
            transcript: transcript(lines),
            maximumTranscriptSegments: 4
        )
        // The tail is what the question is about; the head is stale context that
        // costs latency mid-call.
        #expect(prompt.user.contains("line number 29"))
        #expect(!prompt.user.contains("line number 0\n"))
    }

    // MARK: - Truncation

    @Test func truncatesLongBodiesAndSaysSo() {
        let long = String(repeating: "word ", count: 2_000)
        let prompt = GroundedPrompt.build(
            question: "Summarise",
            page: page(body: long),
            transcript: [],
            maximumBodyCharacters: 200
        )
        // The marker matters: a body cut mid-sentence reads as a page that simply
        // ends, which invites the model to fill the gap.
        #expect(prompt.user.contains("[page truncated]"))
        #expect(prompt.user.count < long.count)
    }

    @Test func doesNotTruncateShortBodies() {
        let prompt = GroundedPrompt.build(
            question: "Summarise",
            page: page(body: "Short body."),
            transcript: []
        )
        #expect(!prompt.user.contains("[page truncated]"))
        #expect(prompt.user.contains("Short body."))
    }

    @Test func truncationBreaksOnAWordBoundary() {
        let truncated = GroundedPrompt.truncate("alpha bravo charlie delta", to: 14)
        #expect(truncated.hasPrefix("alpha bravo"))
        #expect(!truncated.contains("charl\n"))
    }

    @Test func structuredFieldsSurviveEvenWhenTheBodyIsTruncatedToNothing() {
        // Status and latest-update carry most of the answer for the commonest
        // question, so they must never be the thing that gets cut.
        let prompt = GroundedPrompt.build(
            question: "What's the status?",
            page: page(body: String(repeating: "x", count: 10_000)),
            transcript: [],
            maximumBodyCharacters: 10
        )
        #expect(prompt.user.contains("In Progress (Deployment phase)"))
        #expect(prompt.user.contains("Visual assets approved yesterday."))
    }

    // MARK: - Quick actions

    @Test func quickActionsMatchTheThreeActionDesignAndSendRicherPrompts() {
        #expect(QuickAction.allCases.count == 3)
        #expect(QuickAction.whatToSay.title == "What should I say?")

        for action in QuickAction.allCases {
            // The button label has to fit a small card; the prompt does not, and
            // sending the bare label would under-specify the request.
            #expect(action.prompt.count > action.title.count)
        }
        #expect(QuickAction.research.prompt.lowercased().contains("contradict"))
    }
}
