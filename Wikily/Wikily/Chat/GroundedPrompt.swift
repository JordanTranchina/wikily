import Foundation

/// Builds the prompt sent to the on-device model when the user asks Wikily
/// something mid-call.
///
/// This is the part that decides whether the feature is useful or embarrassing.
/// A small on-device model asked a support question cold will answer
/// confidently and wrongly — and the user is about to repeat that answer to a
/// customer, out loud, in real time. So the prompt does three things, in
/// priority order:
///
///  1. **Grounds the answer in the matched wiki page.** The page is the reason
///     Wikily exists; the model's job is to read it and answer from it, not to
///     know things.
///  2. **Includes what was just said.** "What should I say?" is meaningless
///     without the last few turns of the call, and it is the single most likely
///     question a user asks.
///  3. **Makes "I don't know" an explicitly acceptable answer.** Left implicit,
///     models invent. Named as the preferred failure, they mostly don't.
///
/// Kept as a pure function over plain values so every one of those properties is
/// testable without a model, a call, or a network.
enum GroundedPrompt {

    struct Prompt: Equatable, Sendable {
        var system: String
        var user: String
    }

    /// How much of the page body to include.
    ///
    /// The on-device model has a modest context window and every extra token is
    /// latency the user waits through mid-call. Titles, status, latest-update and
    /// blocker lines are the high-value fields and are always included in full;
    /// the body is the part that gets truncated.
    static let maximumBodyCharacters = 1_500

    /// How many recent turns of the call to include.
    ///
    /// Enough to capture the question being asked and its setup, without
    /// re-sending the whole call on every follow-up.
    static let maximumTranscriptSegments = 8

    static let systemPrompt = """
        You are Wikily, assisting someone who is on a live call right now. \
        They will read your answer aloud or act on it within seconds, so be brief \
        and concrete.

        Rules:
        - Answer using ONLY the wiki page and call transcript provided below. \
        Do not use outside knowledge, and do not guess.
        - If the material does not contain the answer, say that the page does not \
        cover it. That is a correct and useful answer, not a failure.
        - Silence is not denial. If the page simply does not mention something, \
        say "the page doesn't say" — never say that it did not happen, was not \
        agreed, or does not exist. Asserting an absence is as wrong as inventing \
        a fact, and the user may repeat it to a customer.
        - Never invent specifics. Do not state a status, date, number, name, or \
        commitment that does not appear in the material.
        - Default to two or three sentences. Use a short list only if the answer \
        is genuinely a list.
        - Where the question asks what to say, give them the line to say, in \
        their own voice. One turn only — never write out a back-and-forth \
        dialogue or script both sides of the call.
        - Write plain prose. No markdown, no bold, no headings, no speaker \
        labels. The answer is rendered as plain text on a small card, so any \
        markup shows up as literal characters.
        - Reply with the answer itself. No preamble, no "based on the wiki page", \
        no restating the question, no apologies.
        """

    /// Assemble the user turn from the matched page, the recent call, and the
    /// question.
    static func build(
        question: String,
        page: WikiDocument?,
        transcript: [TranscriptSegment],
        maximumBodyCharacters: Int = maximumBodyCharacters,
        maximumTranscriptSegments: Int = maximumTranscriptSegments
    ) -> Prompt {
        var sections: [String] = []

        if let page {
            sections.append(
                pageSection(page, maximumBodyCharacters: maximumBodyCharacters)
            )
        } else {
            // Stated rather than omitted: without it the model tends to assume a
            // page was provided and answer as though it had read one.
            sections.append(
                "WIKI PAGE:\nNo wiki page matched the current conversation."
            )
        }

        let recent = transcript.suffix(maximumTranscriptSegments)
        if recent.isEmpty {
            sections.append("CALL SO FAR:\nNothing has been transcribed yet.")
        } else {
            let lines = recent.map { "\($0.speakerLabel): \($0.text)" }
            sections.append("CALL SO FAR:\n" + lines.joined(separator: "\n"))
        }

        sections.append("QUESTION:\n\(question.trimmed)")

        return Prompt(system: systemPrompt, user: sections.joined(separator: "\n\n"))
    }

    // MARK: - Page rendering

    private static func pageSection(
        _ page: WikiDocument,
        maximumBodyCharacters: Int
    ) -> String {
        var lines = ["WIKI PAGE: \(page.title)"]

        // The structured fields carry most of the answer for a status question,
        // and they are short, so they are never truncated.
        if let status = page.status, !status.isEmpty {
            lines.append("Status: \(status)")
        }
        if let latest = page.latestUpdate, !latest.isEmpty {
            lines.append("Latest update: \(latest)")
        }
        if let blocker = page.blocker, !blocker.isEmpty {
            lines.append("Blocker: \(blocker)")
        }
        if !page.summary.isEmpty {
            lines.append("Summary: \(page.summary)")
        }

        let body = truncate(page.body, to: maximumBodyCharacters)
        if !body.isEmpty {
            lines.append("")
            lines.append(body)
        }

        return lines.joined(separator: "\n")
    }

    /// Truncate on a word boundary and say so.
    ///
    /// The marker matters: a body cut mid-sentence reads to the model as though
    /// the page simply ends there, which invites it to fill the gap.
    static func truncate(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmed
        guard trimmed.count > limit else { return trimmed }

        let cut = trimmed.prefix(limit)
        let boundary = cut.lastIndex(of: " ") ?? cut.endIndex
        return cut[..<boundary].trimmed + "\n[page truncated]"
    }
}

/// The fixed prompts offered as one-click buttons on the card.
///
/// Fixed rather than user-editable by decision: an editor is a settings page for
/// something most people never touch. Three actions, matching the Claude Design
/// "Floating assistant widget" wireframe (`Floating Assistant Widget.dc.html`,
/// project `Wikily screen wireframes`) — narrowed from the original four
/// (Fact-check renamed to Research with the same prompt; Recap dropped) when
/// that redesign shipped.
enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case whatToSay = "What should I say?"
    case followUp = "Follow-up questions"
    case research = "Research"

    var id: String { rawValue }

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .whatToSay: "text.bubble"
        case .followUp: "questionmark.circle"
        case .research: "globe"
        }
    }

    /// The question actually sent, which is more specific than the button label.
    /// The label has to fit on a small card; the prompt does not.
    ///
    /// Deliberately free of "based on the wiki page and the call" phrasing. The
    /// system prompt already establishes grounding, and repeating it here made
    /// the model open every answer by echoing it back — burning the first line
    /// of a small card on preamble.
    var prompt: String {
        switch self {
        case .whatToSay:
            // Not "give me the exact words" — that phrasing made the model
            // write out a whole two-sided dialogue instead of one reply.
            "What should I say next?"
        case .followUp:
            "What follow-up questions should I ask next?"
        case .research:
            "Does anything said in the call so far contradict the wiki page? Quote the specific conflict, or say nothing conflicts."
        }
    }
}
