import Foundation
import OSLog

/// Runs one transcriber per capture source and merges their output into a single
/// ordered conversation.
///
/// `SpeechAnalyzer` consumes one input sequence, so the system tap and the
/// microphone each need their own instance. Merging here — rather than in the
/// UI — means everything downstream sees one conversation with speaker labels,
/// which is what the wiki matcher and the HUD both actually want.
actor LiveTranscriber {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "LiveTranscriber")

    private let locale: Locale
    private var transcribers: [AudioChunk.Source: SpeechAnalyzerTranscriber] = [:]
    private var forwardingTasks: [Task<Void, Never>] = []

    private let segmentStream: AsyncStream<TranscriptSegment>
    private let segmentContinuation: AsyncStream<TranscriptSegment>.Continuation

    /// Merged, speaker-attributed transcript segments.
    nonisolated let segments: AsyncStream<TranscriptSegment>

    init(locale: Locale) {
        self.locale = locale
        let (stream, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        self.segmentStream = stream
        self.segmentContinuation = continuation
        self.segments = stream
    }

    /// Start a transcriber for each source that will actually be captured.
    func start(sources: [AudioChunk.Source]) async throws {
        for source in sources {
            let transcriber = SpeechAnalyzerTranscriber(locale: locale, source: source)
            try await transcriber.start()
            transcribers[source] = transcriber

            forwardingTasks.append(
                Task { [segmentContinuation] in
                    for await segment in transcriber.segments {
                        segmentContinuation.yield(segment)
                    }
                }
            )
        }
    }

    /// Route a captured chunk to the transcriber for its source.
    func feed(_ chunk: AudioChunk) async {
        await transcribers[chunk.source]?.feed(chunk)
    }

    func finish() async {
        for transcriber in transcribers.values {
            await transcriber.finish()
        }
        transcribers.removeAll()
        forwardingTasks.forEach { $0.cancel() }
        forwardingTasks.removeAll()
        segmentContinuation.finish()
    }
}
