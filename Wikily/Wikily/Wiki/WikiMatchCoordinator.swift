import Foundation

/// How eagerly the overlay surfaces a suggestion.
///
/// Implemented as the size of the sliding transcript window fed to the matcher:
/// a smaller window reacts to the latest utterance faster (more suggestions), a
/// larger one smooths over a longer stretch of the call (fewer, steadier ones).
enum WikiSuggestionFrequency: String, Sendable, CaseIterable, Codable {
    case low, medium, high

    /// Number of recent utterances that form the match window.
    var windowSize: Int {
        switch self {
        case .high: 2
        case .medium: 4
        case .low: 6
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// Named confidence presets shown in Settings → Behavior. The stored value is
/// still the raw `0...1` threshold used by the matcher.
enum WikiConfidencePreset: String, Sendable, CaseIterable, Codable {
    case low, medium, high

    var threshold: Double {
        switch self {
        case .low: 0.2
        case .medium: WikiMatchCoordinator.defaultThreshold
        case .high: 0.55
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Nearest preset for an arbitrary stored threshold.
    static func closest(to threshold: Double) -> WikiConfidencePreset {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .medium
    }
}

/// Decides *when* a proactive card should appear, given a stream of utterances.
///
/// Owns the sliding transcript window, the confidence gate, and the suppression
/// rules. Kept as a plain value type with an injected clock so every rule below
/// is unit-testable without audio, a UI, or real time passing.
///
/// Ported from the `runWikiMatch` closure in `src/hooks/useSystemAudio.ts`, with
/// one behavioural addition. The original fires the matcher on every single
/// utterance with no rate limiting, so a caller who stays on one topic re-triggers
/// the same card continuously. Two suppression rules fix that: a minimum interval
/// between cards, and a cooldown before the same document can surface again.
struct WikiMatchCoordinator: Sendable {

    static let defaultThreshold = 0.35

    /// Minimum time between two surfaced cards, regardless of document.
    /// Below this the overlay visibly flickers as scores cross the threshold.
    var minimumInterval: TimeInterval = 2

    /// How long before the *same* document may surface again. The card stays on
    /// screen until dismissed, so re-surfacing it is invisible churn.
    var repeatCooldown: TimeInterval = 45

    var threshold: Double = defaultThreshold
    var suggestionFrequency: WikiSuggestionFrequency = .medium

    private var window: [String] = []
    private var dismissedDocumentID: String?
    private var lastSurfacedAt: Date?
    private var lastSurfacedDocumentID: String?

    init(
        threshold: Double = defaultThreshold,
        suggestionFrequency: WikiSuggestionFrequency = .medium
    ) {
        self.threshold = threshold
        self.suggestionFrequency = suggestionFrequency
    }

    /// The current sliding window, oldest first. Exposed for diagnostics.
    var currentWindow: [String] { window }

    /// Feed the newest utterance and return a match if one should be shown now.
    ///
    /// Returning `nil` covers several distinct cases — below threshold, rate
    /// limited, suppressed — deliberately collapsed, because the caller's
    /// response to all of them is identical: leave the overlay as it is.
    mutating func ingest(
        utterance: String,
        index: WikiIndex,
        now: Date = Date()
    ) -> WikiMatch? {
        window.append(utterance)
        let size = suggestionFrequency.windowSize
        if window.count > size {
            window.removeFirst(window.count - size)
        }

        let windowText = window.joined(separator: " ")
        guard let top = WikiMatcher.match(index: index, transcript: windowText).first,
              top.score >= threshold
        else { return nil }

        // A card the user just dismissed stays suppressed until a *different*
        // document matches — dismissing means "not this, right now".
        if top.document.id == dismissedDocumentID { return nil }
        dismissedDocumentID = nil

        if let lastSurfacedAt, now.timeIntervalSince(lastSurfacedAt) < minimumInterval {
            return nil
        }
        if top.document.id == lastSurfacedDocumentID,
           let lastSurfacedAt,
           now.timeIntervalSince(lastSurfacedAt) < repeatCooldown {
            return nil
        }

        lastSurfacedAt = now
        lastSurfacedDocumentID = top.document.id
        return top
    }

    /// Suppress the given document until something else matches.
    mutating func dismiss(documentID: String) {
        dismissedDocumentID = documentID
    }

    /// Clear all state. Called when a call starts or ends.
    mutating func reset() {
        window.removeAll()
        dismissedDocumentID = nil
        lastSurfacedAt = nil
        lastSurfacedDocumentID = nil
    }
}
