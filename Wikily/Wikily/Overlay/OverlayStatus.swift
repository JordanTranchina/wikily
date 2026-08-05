import Foundation

/// What the toolbar's status icon shows — one of five states, from the Claude
/// Design "Floating assistant widget" wireframe (`Floating Assistant Widget.dc.html`,
/// project `Wikily screen wireframes`). Pure over `CallSession`'s published
/// state so the mapping is testable without a window, a panel, or real audio.
enum OverlayStatus: Equatable {
    case idle
    case listening
    case thinking
    case researching
    case ready

    /// Priority, highest first: an in-flight ask always wins over a matched
    /// page — the icon has to stay honest about what Wikily is doing *right
    /// now*, not what it found earlier. A match beats plain listening, and
    /// listening beats idle.
    @MainActor
    init(session: CallSession) {
        if session.askSession.isAnswering {
            self = session.askSession.runningAction == .research ? .researching : .thinking
        } else if session.currentMatch != nil {
            self = .ready
        } else if session.isListening {
            self = .listening
        } else {
            self = .idle
        }
    }
}
