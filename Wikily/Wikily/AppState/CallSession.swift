import Foundation
import OSLog

/// The single observable surface the overlay renders.
///
/// Everything below this object is an actor with its own stream — capture,
/// transcription, matching. Everything above it is a SwiftUI view. This is the
/// one place the three are wired together, which is deliberate: it keeps the
/// views free of `async` plumbing and keeps the plumbing free of AppKit, so the
/// interesting half (a transcript turning into a suggestion) can be tested by
/// pushing segments through `ingest(_:)` with no audio, no model and no window.
///
/// Replaces `useSystemAudio.ts`, which held the same responsibilities plus the
/// React render loop.
@MainActor
@Observable
final class CallSession {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "CallSession")

    enum Phase: Sendable, Equatable {
        case idle
        /// Permissions, model check and device setup — briefly, on start.
        case starting
        case listening
    }

    // MARK: - Published state

    private(set) var phase: Phase = .idle

    var isListening: Bool { phase == .listening }

    /// Someone is speaking right now, from the VAD rather than the recogniser.
    /// Drives the pulsing dot, which is why it is allowed to be approximate: it
    /// is a liveness cue, not a transcript.
    private(set) var isSpeechActive = false

    /// Recent finalised segments, oldest first, capped — a call runs for an hour
    /// and the HUD shows the last few lines.
    private(set) var transcript: [TranscriptSegment] = []

    /// The suggestion currently on screen, or `nil` while nothing matches.
    private(set) var currentMatch: WikiMatch?

    /// Last failure, in words a user can act on. Cleared on the next start.
    private(set) var errorMessage: String?

    private(set) var index: WikiIndex = .empty

    /// The wiki folder currently indexed, if one has been chosen.
    private(set) var wikiFolderPath: String?

    // MARK: - Configuration

    static let transcriptLimit = 40

    /// How long after the last speech event the "speaking" cue stays lit. The VAD
    /// reports speech *starting*, never stopping, so the cue needs a decay or it
    /// would latch on for the rest of the call.
    var speechActivityHold: Duration = .milliseconds(1200)

    static let wikiFolderDefaultsKey = "wiki.folderPath"

    // MARK: - Internals

    private var coordinator: WikiMatchCoordinator
    private let now: @Sendable () -> Date

    private var capture: CallCaptureSession?
    private var transcriber: LiveTranscriber?
    private var audioTask: Task<Void, Never>?
    private var segmentTask: Task<Void, Never>?
    private var speechDecayTask: Task<Void, Never>?

    /// - Parameter now: injected so the coordinator's rate limiting can be driven
    ///   by a test clock instead of by real elapsed time.
    init(
        coordinator: WikiMatchCoordinator = WikiMatchCoordinator(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.now = now
    }

    // MARK: - Wiki index

    /// Scan, parse and index a folder of markdown, then keep it as the live index.
    ///
    /// The work happens off the main actor because a large vault takes long
    /// enough to drop frames, and this can be triggered mid-call.
    func loadWiki(directory path: String) async {
        do {
            index = try await Self.buildIndex(directory: path)
            wikiFolderPath = path
            UserDefaults.standard.set(path, forKey: Self.wikiFolderDefaultsKey)
            errorMessage = nil
            logger.info("Indexed \(self.index.documents.count, privacy: .public) wiki pages")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Wiki index failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-index the folder chosen in a previous launch, if it is still there.
    func restorePersistedWiki() async {
        guard let path = UserDefaults.standard.string(forKey: Self.wikiFolderDefaultsKey) else {
            return
        }
        await loadWiki(directory: path)
    }

    private static func buildIndex(directory: String) async throws -> WikiIndex {
        try await Task.detached(priority: .userInitiated) {
            let scan = try WikiScanner.scan(directory: directory)
            return WikiIndexBuilder.build(scan.files.map(MarkdownParser.parse))
        }.value
    }

    // MARK: - Listening

    /// Start capturing and transcribing the current call.
    ///
    /// Every failure path leaves `phase` back at `.idle` with `errorMessage` set,
    /// because a half-started session that still reports itself as listening is
    /// worse than one that plainly failed — the user would sit through a call
    /// waiting for suggestions that can never come.
    func startListening() async {
        guard phase == .idle else { return }
        phase = .starting
        errorMessage = nil
        currentMatch = nil
        transcript.removeAll()
        coordinator.reset()

        guard let locale = await SpeechModelInstaller.resolvedLocale() else {
            fail("On-device transcription isn't available on this Mac.")
            return
        }
        guard await SpeechModelInstaller.state(for: locale).isReady else {
            fail("The speech model for \(locale.identifier) isn't installed yet.")
            return
        }

        let capture = CallCaptureSession()
        let transcriber = LiveTranscriber(
            locale: locale,
            contextualStrings: index.recognitionVocabulary()
        )

        let events: AsyncStream<CallCaptureSession.Event>
        do {
            events = try await capture.start(configuration: .init())
            try await transcriber.start(sources: await capture.activeSources)
        } catch {
            await capture.stop()
            fail(error.localizedDescription)
            return
        }

        self.capture = capture
        self.transcriber = transcriber
        phase = .listening

        // Detached on purpose: this loop runs at audio rate, and hopping it
        // through the main actor for every chunk would put capture cadence at the
        // mercy of whatever the UI is doing.
        audioTask = Task.detached { [weak self] in
            for await event in events {
                switch event {
                case .audio(let chunk):
                    await transcriber.feed(chunk)
                case .speechStarted:
                    await self?.noteSpeechStarted()
                case .utterance:
                    // VAD segmentation only feeds the diagnostics WAV dumps; the
                    // analyzer does its own endpointing from the raw stream.
                    break
                }
            }
        }

        segmentTask = Task { [weak self] in
            for await segment in transcriber.segments {
                self?.ingest(segment)
            }
        }
    }

    /// Stop capturing, flushing whatever was mid-recognition.
    func stopListening() async {
        guard phase != .idle else { return }

        let capture = self.capture
        let transcriber = self.transcriber
        self.capture = nil
        self.transcriber = nil

        // Order matters. Stopping capture finishes the event stream, which ends
        // the audio pump on its own; only then can the transcriber be finalised
        // without racing a feed. Cancelling the pump first would drop audio that
        // is already captured but not yet handed over.
        await capture?.stop()
        await audioTask?.value
        audioTask = nil

        await transcriber?.finish()
        await segmentTask?.value
        segmentTask = nil

        speechDecayTask?.cancel()
        speechDecayTask = nil
        isSpeechActive = false
        phase = .idle
    }

    func toggleListening() async {
        if phase == .idle {
            await startListening()
        } else {
            await stopListening()
        }
    }

    // MARK: - Match pipeline

    /// Feed one finalised segment through the matcher.
    ///
    /// The live path and the tests both come through here, which is the point:
    /// what a scripted call proves about suggestions is then true of a real one.
    func ingest(_ segment: TranscriptSegment) {
        transcript.append(segment)
        if transcript.count > Self.transcriptLimit {
            transcript.removeFirst(transcript.count - Self.transcriptLimit)
        }

        guard !index.documents.isEmpty else { return }
        if let match = coordinator.ingest(utterance: segment.text, index: index, now: now()) {
            currentMatch = match
        }
    }

    /// Clear the current suggestion and suppress that page until the topic moves.
    func dismissCurrentMatch() {
        guard let currentMatch else { return }
        coordinator.dismiss(documentID: currentMatch.document.id)
        self.currentMatch = nil
    }

    /// Apply the user's sensitivity settings without disturbing the sliding
    /// window — these are adjustable mid-call.
    func configureMatching(
        threshold: Double? = nil,
        suggestionFrequency: WikiSuggestionFrequency? = nil
    ) {
        if let threshold { coordinator.threshold = threshold }
        if let suggestionFrequency { coordinator.suggestionFrequency = suggestionFrequency }
    }

    func noteSpeechStarted() {
        isSpeechActive = true
        speechDecayTask?.cancel()
        speechDecayTask = Task { [speechActivityHold] in
            try? await Task.sleep(for: speechActivityHold)
            guard !Task.isCancelled else { return }
            self.isSpeechActive = false
        }
    }

    /// Report as listening without starting capture — `--overlay-preview` only.
    ///
    /// The alternative for checking the HUD is recording a real call, which is a
    /// disproportionate thing to require for a layout change. Nothing else calls
    /// this, and it touches no audio state.
    func enterPreviewListening() {
        phase = .listening
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .idle
        logger.error("Listening failed: \(message, privacy: .public)")
    }
}
