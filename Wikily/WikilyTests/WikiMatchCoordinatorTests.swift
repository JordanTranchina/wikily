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

    @Test func confidencePresetsMapBackToTheNearestNamedValue() {
        #expect(WikiConfidencePreset.closest(to: 0.2) == .low)
        #expect(WikiConfidencePreset.closest(to: 0.35) == .medium)
        #expect(WikiConfidencePreset.closest(to: 0.6) == .high)
    }
}
