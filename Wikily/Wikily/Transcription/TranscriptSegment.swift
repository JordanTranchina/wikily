import Foundation

/// A stretch of recognised speech, attributed to one side of the call.
struct TranscriptSegment: Sendable, Equatable, Identifiable {
    let id = UUID()
    var text: String
    var source: AudioChunk.Source
    /// Seconds from the start of capture, for ordering the two sources into one
    /// conversation.
    var startTime: TimeInterval

    /// How the speaker reads in the UI.
    var speakerLabel: String {
        switch source {
        case .system: "Them"
        case .microphone: "You"
        }
    }

    static func == (lhs: TranscriptSegment, rhs: TranscriptSegment) -> Bool {
        lhs.text == rhs.text && lhs.source == rhs.source && lhs.startTime == rhs.startTime
    }
}

/// Anything that turns captured audio into text.
///
/// A protocol rather than a concrete type so the wiki-matching path can be
/// driven by a scripted fake in tests — the real implementation needs an
/// installed model, a permission grant and live audio, none of which belong in a
/// unit test.
protocol TranscriptionService: Actor {
    /// Finalised transcript segments, in the order they were recognised.
    var segments: AsyncStream<TranscriptSegment> { get }

    func start() async throws
    func feed(_ chunk: AudioChunk) async
    func finish() async
}
