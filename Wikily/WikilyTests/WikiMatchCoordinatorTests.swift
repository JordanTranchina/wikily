import Foundation
import Testing
@testable import Wikily

/// Covers the suppression rules that decide *when* a card appears.
///
/// These have no TypeScript counterpart: the original fires the matcher on every
/// utterance with no rate limiting. Time is injected so the cooldowns are tested
/// without any real waiting.
struct WikiMatchCoordinatorTests {

    private let index = WikiIndexBuilder.build(WikiEngineTests.files.map(MarkdownParser.parse))
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeCoordinator() -> WikiMatchCoordinator {
        WikiMatchCoordinator(threshold: 0.3, suggestionFrequency: .medium)
    }

    @Test func surfacesAMatchOnceTheThresholdIsCleared() throws {
        var coordinator = makeCoordinator()
        let result = coordinator.ingest(
            utterance: "any update on the Becky promotion?",
            index: index,
            now: start
        )
        let match = try #require(result)
        #expect(match.document.id == "/wiki/becky-promotion.md")
    }

    @Test func staysSilentBelowThreshold() {
        var coordinator = makeCoordinator()
        let match = coordinator.ingest(
            utterance: "Did you watch the game last night?",
            index: index,
            now: start
        )
        #expect(match == nil)
    }

    @Test func suppressesASecondCardInsideTheMinimumInterval() {
        var coordinator = makeCoordinator()
        coordinator.minimumInterval = 2

        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        // A different document, but only half a second later.
        let tooSoon = coordinator.ingest(
            utterance: "now about the OAuth redirect URI for Sandbox",
            index: index,
            now: start.addingTimeInterval(0.5)
        )
        #expect(tooSoon == nil)
    }

    @Test func allowsADifferentDocumentOnceTheIntervalHasPassed() throws {
        var coordinator = makeCoordinator()
        coordinator.minimumInterval = 2
        coordinator.suggestionFrequency = .high  // small window, so the topic actually changes

        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        _ = coordinator.ingest(utterance: "anyway", index: index, now: start.addingTimeInterval(3))
        let result = coordinator.ingest(
            utterance: "the OAuth redirect URI for our Sandbox environment",
            index: index,
            now: start.addingTimeInterval(6)
        )
        let next = try #require(result)
        #expect(next.document.id == "/wiki/oauth-sandbox.md")
    }

    @Test func doesNotRepeatTheSameDocumentInsideTheCooldown() {
        var coordinator = makeCoordinator()
        coordinator.minimumInterval = 2
        coordinator.repeatCooldown = 45

        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        // Well past the minimum interval, still inside the repeat cooldown.
        let repeated = coordinator.ingest(
            utterance: "more on the Becky promotion",
            index: index,
            now: start.addingTimeInterval(10)
        )
        #expect(repeated == nil)
    }

    @Test func repeatsTheSameDocumentAfterTheCooldown() throws {
        var coordinator = makeCoordinator()
        coordinator.repeatCooldown = 45

        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        let result = coordinator.ingest(
            utterance: "back to the Becky promotion",
            index: index,
            now: start.addingTimeInterval(60)
        )
        let repeated = try #require(result)
        #expect(repeated.document.id == "/wiki/becky-promotion.md")
    }

    @Test func dismissedDocumentStaysSuppressed() {
        var coordinator = makeCoordinator()
        coordinator.minimumInterval = 0
        coordinator.repeatCooldown = 0

        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        coordinator.dismiss(documentID: "/wiki/becky-promotion.md")

        let suppressed = coordinator.ingest(
            utterance: "still the Becky promotion",
            index: index,
            now: start.addingTimeInterval(120)
        )
        #expect(suppressed == nil)
    }

    @Test func resetClearsWindowAndSuppression() throws {
        var coordinator = makeCoordinator()
        _ = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        coordinator.dismiss(documentID: "/wiki/becky-promotion.md")
        coordinator.reset()

        #expect(coordinator.currentWindow.isEmpty)
        let result = coordinator.ingest(utterance: "the Becky promotion", index: index, now: start)
        let afterReset = try #require(result)
        #expect(afterReset.document.id == "/wiki/becky-promotion.md")
    }

    @Test func windowIsTrimmedToTheFrequencySetting() {
        var coordinator = makeCoordinator()
        coordinator.suggestionFrequency = .high  // window size 2

        for utterance in ["one", "two", "three", "four"] {
            _ = coordinator.ingest(utterance: utterance, index: index, now: start)
        }
        #expect(coordinator.currentWindow == ["three", "four"])
    }

    @Test func matchesAcrossUtterancesUsingTheSlidingWindow() throws {
        // The trigger phrase is split over two utterances; neither alone would
        // produce the entity hit, but the window joins them.
        var coordinator = makeCoordinator()
        #expect(coordinator.ingest(utterance: "any update on the", index: index, now: start) == nil)
        let result = coordinator.ingest(
            utterance: "Becky promotion campaign?",
            index: index,
            now: start.addingTimeInterval(3)
        )
        let match = try #require(result)
        #expect(match.document.id == "/wiki/becky-promotion.md")
    }

    // MARK: - Topic changes mid-call
    //
    // These cover a bug that only showed up on a real recording. Scoring the
    // whole sliding window meant a strong entity hit early in a call ("the Becky
    // promotion") kept its boost for as long as it stayed in the window, so it
    // outranked whatever the caller moved on to. That stale top match was then
    // suppressed by its own repeat cooldown — and because `ingest` returned nil
    // as soon as the *top* candidate was suppressed, every later topic was
    // discarded with it. The overlay went deaf for 45 seconds after its first
    // suggestion. Three real pages scoring 94–100% surfaced nothing.

    /// An index where the first topic's entity boost deliberately dominates any
    /// window it appears in, reproducing the conditions above.
    private func twoTopicIndex() -> WikiIndex {
        let alpha = MarkdownParser.parse(RawWikiFile(
            path: "/wiki/alpha.md",
            name: "alpha",
            content: """
            ---
            title: "Alpha Widget Calibration"
            aliases: ["alpha widget", "widget calibration", "alpha calibration"]
            tags: [alpha, calibration, widget]
            ---

            # Alpha Widget Calibration

            How to calibrate the alpha widget before shipping.
            """
        ))
        let beta = MarkdownParser.parse(RawWikiFile(
            path: "/wiki/beta.md",
            name: "beta",
            content: """
            ---
            title: "Beta Shipping Rates"
            tags: [shipping]
            ---

            # Beta Shipping Rates

            Current shipping rates for beta customers.
            """
        ))
        return WikiIndexBuilder.build([alpha, beta])
    }

    @Test func aNewTopicSurfacesEvenWhileTheEarlierPageIsInCooldown() throws {
        let index = twoTopicIndex()
        var coordinator = WikiMatchCoordinator(threshold: 0.3)

        let first = coordinator.ingest(
            utterance: "walk me through the alpha widget calibration",
            index: index,
            now: start
        )
        #expect(try #require(first).document.id == "/wiki/alpha.md")

        // Past the minimum interval, but well inside alpha's 45s repeat cooldown.
        let second = coordinator.ingest(
            utterance: "and what are the beta shipping rates",
            index: index,
            now: start.addingTimeInterval(10)
        )
        let match = try #require(second, "the second topic was silently discarded")
        #expect(match.document.id == "/wiki/beta.md")
    }

    @Test func theCurrentUtteranceOutranksAStaleEntityStillInTheWindow() throws {
        let index = twoTopicIndex()
        var coordinator = WikiMatchCoordinator(threshold: 0.3)
        coordinator.repeatCooldown = 0  // isolate window staleness from cooldown

        _ = coordinator.ingest(
            utterance: "walk me through the alpha widget calibration",
            index: index,
            now: start
        )
        let second = coordinator.ingest(
            utterance: "and what are the beta shipping rates",
            index: index,
            now: start.addingTimeInterval(10)
        )
        // The window still contains the alpha text, whose entity boost is the
        // larger of the two. What is being discussed *now* has to win anyway.
        #expect(try #require(second).document.id == "/wiki/beta.md")
    }

    @Test func fallsThroughPastADismissedPageToTheNextCandidate() throws {
        let index = twoTopicIndex()
        var coordinator = WikiMatchCoordinator(threshold: 0.3)
        coordinator.minimumInterval = 0

        let first = coordinator.ingest(
            utterance: "alpha widget calibration and beta shipping rates",
            index: index,
            now: start
        )
        let top = try #require(first)
        coordinator.dismiss(documentID: top.document.id)

        // Same sentence, so the dismissed page is still the top match. The
        // runner-up should surface rather than nothing at all.
        let second = coordinator.ingest(
            utterance: "alpha widget calibration and beta shipping rates",
            index: index,
            now: start.addingTimeInterval(10)
        )
        #expect(try #require(second).document.id != top.document.id)
    }

    /// The recorded call from the diagnostics run, as a regression test.
    @Test func aRealCallSurfacesEachTopicInTurn() throws {
        let vault = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
        let index = WikiIndexBuilder.build(
            try WikiScanner.scan(directory: vault).files.map(MarkdownParser.parse)
        )

        // Transcribed verbatim from a real recording, mis-recognitions included:
        // "OAuth" came back as "OOS", and the matcher still resolves the page
        // from the surrounding vocabulary.
        let call = [
            "Hey, thanks for hopping on. How's your week going?",
            "Good, good. So 1st thing, I wanted an update on a Becky promotion campaign. Where did that land?",
            "Right. Second, we're still having trouble setting up the OOS redirect URI for our sandbox environment.",
            "And the last one, the customer keeps hitting a rate limit on the API. What are the actual numbers there?",
        ]

        var coordinator = WikiMatchCoordinator()
        var surfaced: [String?] = []
        var clock = start
        for utterance in call {
            clock = clock.addingTimeInterval(10)
            surfaced.append(
                coordinator.ingest(utterance: utterance, index: index, now: clock)?
                    .document.title
            )
        }

        #expect(surfaced[0] == nil, "small talk must not surface a page")
        #expect(surfaced[1]?.contains("Becky") == true)
        #expect(surfaced[2]?.contains("OAuth") == true)
        #expect(surfaced[3]?.contains("Rate Limits") == true)
    }

    @Test func confidencePresetsMapBackToTheNearestNamedValue() {
        #expect(WikiConfidencePreset.closest(to: 0.2) == .low)
        #expect(WikiConfidencePreset.closest(to: 0.35) == .medium)
        #expect(WikiConfidencePreset.closest(to: 0.6) == .high)
    }
}
