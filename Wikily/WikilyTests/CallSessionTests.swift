import Foundation
import Testing
@testable import Wikily

/// Covers the app-state wiring: a sequence of transcript segments in, the right
/// published suggestion out.
///
/// This is the layer worth testing hardest. The views below it are a rendering
/// of these properties, and the actors above it (capture, transcription) need
/// audio and an installed model, so they are verified by the diagnostics modes.
/// Everything the *product* promises — the right page at the right moment, and
/// silence otherwise — is decided here.
@MainActor
struct CallSessionTests {

    private static var sampleVaultPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
    }

    /// A session with the sample vault indexed and a controllable clock.
    ///
    /// The clock advances four seconds per segment, mirroring a real call's
    /// pacing, so the coordinator's rate limiting is exercised rather than
    /// bypassed.
    private func makeSession(threshold: Double = 0.3) async -> (CallSession, Clock) {
        let clock = Clock()
        var coordinator = WikiMatchCoordinator(threshold: threshold)
        coordinator.minimumInterval = 0
        let session = CallSession(coordinator: coordinator, now: { clock.now })
        await session.loadWiki(directory: Self.sampleVaultPath)
        return (session, clock)
    }

    /// A test clock. A class so the session's `@Sendable` closure and the test
    /// body observe the same value.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 0)

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            value = value.addingTimeInterval(seconds)
        }
    }

    private func play(_ script: [TranscriptSegment], into session: CallSession, clock: Clock) {
        for segment in script {
            clock.advance(4)
            session.ingest(segment)
        }
    }

    // MARK: - Index

    @Test func loadingAWikiFolderPopulatesTheIndex() async {
        let (session, _) = await makeSession()
        #expect(session.index.documents.count > 0)
        #expect(session.wikiFolderPath == Self.sampleVaultPath)
        #expect(session.errorMessage == nil)
    }

    @Test func aMissingWikiFolderSurfacesAnErrorRatherThanCrashing() async {
        let session = CallSession()
        await session.loadWiki(directory: "/nope/does/not/exist")
        #expect(session.errorMessage != nil)
        #expect(session.index.documents.isEmpty)
    }

    // MARK: - Transcript to published match

    @Test func aScriptedCallPublishesTheRightPageAtTheRightMoment() async {
        let (session, clock) = await makeSession()

        let smallTalk = [
            TranscriptSegment(text: "Hey, thanks for hopping on.", source: .microphone, startTime: 0),
            TranscriptSegment(text: "No problem at all, how's your week going?", source: .system, startTime: 3),
            TranscriptSegment(text: "Not bad. So what did you want to go over?", source: .microphone, startTime: 7),
        ]
        play(smallTalk, into: session, clock: clock)

        // Small talk must not surface a card — a false positive mid-call is worse
        // than no suggestion at all.
        #expect(session.currentMatch == nil)

        play(
            [TranscriptSegment(
                text: "I wanted an update on the Becky promotion.",
                source: .system,
                startTime: 11
            )],
            into: session,
            clock: clock
        )

        let match = session.currentMatch
        #expect(match != nil)
        #expect(match?.document.title.contains("Becky") == true)
    }

    @Test func anEntirelyOffTopicCallPublishesNothing() async {
        let (session, clock) = await makeSession()

        play(
            [
                "Did you catch the game last night?",
                "I did, terrible weather for it though.",
                "Right? Anyway, good talking to you.",
            ].enumerated().map { index, text in
                TranscriptSegment(text: text, source: .system, startTime: Double(index) * 4)
            },
            into: session,
            clock: clock
        )

        #expect(session.currentMatch == nil)
    }

    /// The transcriber is running, but no wiki has been chosen yet. The HUD must
    /// still show the conversation rather than looking dead.
    @Test func transcriptIsPublishedEvenWithNoIndex() {
        let session = CallSession()
        session.ingest(TranscriptSegment(text: "anything at all", source: .system, startTime: 0))

        #expect(session.transcript.count == 1)
        #expect(session.currentMatch == nil)
    }

    @Test func theTranscriptIsCappedSoALongCallCannotGrowUnbounded() {
        let session = CallSession()
        for index in 0..<(CallSession.transcriptLimit + 25) {
            session.ingest(
                TranscriptSegment(text: "line \(index)", source: .system, startTime: Double(index))
            )
        }

        #expect(session.transcript.count == CallSession.transcriptLimit)
        // The cap must drop the *oldest* lines: the HUD shows the newest.
        #expect(session.transcript.last?.text == "line \(CallSession.transcriptLimit + 24)")
    }

    // MARK: - Dismissal

    @Test func dismissingClearsTheCardAndSuppressesThatPage() async {
        let (session, clock) = await makeSession()
        let becky = TranscriptSegment(
            text: "I wanted an update on the Becky promotion.",
            source: .system,
            startTime: 0
        )

        play([becky], into: session, clock: clock)
        let dismissedID = session.currentMatch?.document.id
        #expect(dismissedID != nil)

        session.dismissCurrentMatch()
        #expect(session.currentMatch == nil)

        // Raising the same topic again must not immediately re-surface the page
        // the user just dismissed.
        play([becky], into: session, clock: clock)
        #expect(session.currentMatch?.document.id != dismissedID)
    }

    @Test func dismissingWithNothingShowingIsHarmless() {
        let session = CallSession()
        session.dismissCurrentMatch()
        #expect(session.currentMatch == nil)
    }

    // MARK: - Liveness

    @Test func speechActivityLightsUpAndThenDecays() async throws {
        let session = CallSession()
        session.speechActivityHold = .milliseconds(50)

        session.noteSpeechStarted()
        #expect(session.isSpeechActive)

        // The VAD reports speech starting but never stopping, so the cue has to
        // time out on its own or it would latch on for the whole call.
        try await Task.sleep(for: .milliseconds(250))
        #expect(!session.isSpeechActive)
    }

    // MARK: - Sensitivity

    @Test func raisingTheThresholdSuppressesAMatchThatWouldOtherwiseFire() async {
        let (session, clock) = await makeSession()
        session.configureMatching(threshold: 0.99)

        play(
            [TranscriptSegment(
                text: "I wanted an update on the Becky promotion.",
                source: .system,
                startTime: 0
            )],
            into: session,
            clock: clock
        )

        #expect(session.currentMatch == nil)
    }

    // MARK: - Lifecycle

    @Test func stoppingWhenIdleIsANoOp() async {
        let session = CallSession()
        await session.stopListening()
        #expect(session.phase == .idle)
        #expect(!session.isListening)
    }
}
