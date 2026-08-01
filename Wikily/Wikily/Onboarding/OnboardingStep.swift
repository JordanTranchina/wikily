import Foundation

/// The three things a new install needs before Wikily can do anything.
///
/// Deliberately short. Everything that *can* be deferred is deferred to
/// Settings — devices, sensitivity, the answering model all have working
/// defaults — and what remains is the two things with no sensible default (a
/// wiki folder, a speech model) plus a hand-off.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case wikiFolder
    case speechModel
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wikiFolder: "Point Wikily at your wiki"
        case .speechModel: "Download the speech model"
        case .done: "You're set"
        }
    }

    var subtitle: String {
        switch self {
        case .wikiFolder:
            "Choose the folder holding your Markdown notes. Wikily reads it on this "
                + "Mac and never uploads any of it."
        case .speechModel:
            "This is the one time Wikily needs the internet. Without this model it "
                + "cannot transcribe a call at all, so nothing else will work."
        case .done:
            "Wikily lives in the menu bar. Start listening from there when a call "
                + "begins, and a card appears when someone mentions a page you have."
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    /// One-based position, for "Step 2 of 3".
    var position: Int { rawValue + 1 }

    static var count: Int { allCases.count }
}
