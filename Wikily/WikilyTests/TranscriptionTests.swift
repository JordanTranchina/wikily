import Foundation
import Testing
@testable import Wikily

/// Covers the transcript layer's testable surface, and — more usefully — the
/// full transcript-to-suggestion path with a scripted transcriber standing in
/// for the real one.
///
/// `SpeechAnalyzerTranscriber` itself needs an installed model, a permission
/// grant and live audio, so it is verified by `--probe-speech` and
/// `--capture-diagnostics` rather than here. What *is* worth pinning down is
/// that a realistic sequence of transcript segments produces the right
/// suggestion at the right moment, which is the actual product behaviour.
struct TranscriptionTests {

    // MARK: - Segment basics

    @Test func speakerLabelsDistinguishTheTwoSidesOfACall() {
        let them = TranscriptSegment(text: "hello", source: .system, startTime: 0)
        let you = TranscriptSegment(text: "hi", source: .microphone, startTime: 1)
        #expect(them.speakerLabel == "Them")
        #expect(you.speakerLabel == "You")
    }

    @Test func segmentsCompareByContentNotIdentity() {
        // Each segment gets a fresh UUID, so equality has to ignore it or
        // deduplication downstream would never match anything.
        let a = TranscriptSegment(text: "same", source: .system, startTime: 2)
        let b = TranscriptSegment(text: "same", source: .system, startTime: 2)
        #expect(a == b)
        #expect(a.id != b.id)
    }

    // MARK: - Diagnostics argument parsing

    @Test func diagnosticModesAreSelectedByLaunchArgument() {
        #expect(CaptureDiagnostics.isProbeRequested(["Wikily", "--probe-audio"]))
        #expect(CaptureDiagnostics.isSpeechProbeRequested(["Wikily", "--probe-speech"]))
        #expect(CaptureDiagnostics.isModelInstallRequested(["Wikily", "--install-speech-model"]))

        // A plain launch must not trigger anything that records or downloads.
        #expect(!CaptureDiagnostics.isProbeRequested(["Wikily"]))
        #expect(!CaptureDiagnostics.isSpeechProbeRequested(["Wikily"]))
        #expect(!CaptureDiagnostics.isModelInstallRequested(["Wikily"]))
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily"]) == nil)
    }

    // MARK: - Transcript to suggestion

    /// A scripted stand-in for the real transcriber.
    ///
    /// Lets the whole downstream path be exercised deterministically: no audio,
    /// no model, no permissions, no timing.
    actor ScriptedTranscriber: TranscriptionService {
        private let script: [TranscriptSegment]
        private let stream: AsyncStream<TranscriptSegment>
        private let continuation: AsyncStream<TranscriptSegment>.Continuation

        nonisolated let segments: AsyncStream<TranscriptSegment>

        init(script: [TranscriptSegment]) {
            self.script = script
            let (stream, continuation) = AsyncStream<TranscriptSegment>.makeStream()
            self.stream = stream
            self.continuation = continuation
            self.segments = stream
        }

        func start() async throws {
            for segment in script {
                continuation.yield(segment)
            }
            continuation.finish()
        }

        func feed(_ chunk: AudioChunk) async {}

        func finish() async {
            continuation.finish()
        }
    }

    private static var sampleVaultPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
    }

    @Test func aScriptedCallSurfacesTheRightPageAtTheRightMoment() async throws {
        let index = WikiIndexBuilder.build(
            try WikiScanner.scan(directory: Self.sampleVaultPath).files.map(MarkdownParser.parse)
        )

        // A plausible support call: small talk, then the real question.
        let script = [
            TranscriptSegment(text: "Hey, thanks for hopping on.", source: .microphone, startTime: 0),
            TranscriptSegment(text: "No problem at all, how's your week going?", source: .system, startTime: 3),
            TranscriptSegment(text: "Not bad. So what did you want to go over?", source: .microphone, startTime: 7),
            TranscriptSegment(text: "I wanted an update on the Becky promotion.", source: .system, startTime: 11),
        ]

        let transcriber = ScriptedTranscriber(script: script)
        try await transcriber.start()

        var coordinator = WikiMatchCoordinator(threshold: 0.3)
        coordinator.minimumInterval = 0
        var surfaced: [WikiMatch] = []
        var clock = Date(timeIntervalSince1970: 0)

        for await segment in transcriber.segments {
            clock = clock.addingTimeInterval(4)
            if let match = coordinator.ingest(
                utterance: segment.text,
                index: index,
                now: clock
            ) {
                surfaced.append(match)
            }
        }

        // Exactly one suggestion, and only once the topic actually came up —
        // small talk must not trigger a card.
        #expect(surfaced.count == 1)
        #expect(surfaced.first?.document.title.contains("Becky") == true)
    }

    @Test func anEntirelyOffTopicCallSurfacesNothing() async throws {
        let index = WikiIndexBuilder.build(
            try WikiScanner.scan(directory: Self.sampleVaultPath).files.map(MarkdownParser.parse)
        )

        let script = [
            "Did you catch the game last night?",
            "I did, terrible weather for it though.",
            "Right? Anyway, good talking to you.",
        ].enumerated().map { index, text in
            TranscriptSegment(text: text, source: .system, startTime: Double(index) * 4)
        }

        let transcriber = ScriptedTranscriber(script: script)
        try await transcriber.start()

        var coordinator = WikiMatchCoordinator(threshold: 0.3)
        var surfaced: [WikiMatch] = []
        var clock = Date(timeIntervalSince1970: 0)

        for await segment in transcriber.segments {
            clock = clock.addingTimeInterval(5)
            if let match = coordinator.ingest(utterance: segment.text, index: index, now: clock) {
                surfaced.append(match)
            }
        }

        #expect(surfaced.isEmpty)
    }
}
