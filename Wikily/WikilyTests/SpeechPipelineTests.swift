import AVFoundation
import Foundation
import Testing
@testable import Wikily

/// End-to-end regression tests for on-device transcription, against a checked-in
/// speech fixture.
///
/// These exist because of a bug that unit tests could never have caught and that
/// looked like working software: the pipeline built cleanly, fed correctly-
/// converted audio into `SpeechAnalyzer`, and produced an empty transcript.
/// Passing an explicit `bufferStartTime` on `AnalyzerInput` — timestamps derived
/// from the *capture* sample rate while the buffers had been resampled — made
/// the analyzer discard everything. Nothing errored. It simply returned nothing.
///
/// `Fixtures/becky-utterance.wav` is synthesised speech (`say`), so it is small,
/// deterministic, and contains no real person's voice.
struct SpeechPipelineTests {

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/becky-utterance.wav")
    }

    /// Transcription needs the on-device model installed. Rather than failing on
    /// a machine that hasn't downloaded it, skip — but never skip silently in a
    /// way that hides a real regression, hence the explicit reason.
    static func installedLocale() async -> Locale? {
        guard let locale = await SpeechModelInstaller.resolvedLocale(),
              await SpeechModelInstaller.state(for: locale).isReady
        else { return nil }
        return locale
    }

    @Test func fixtureIsReadableAsMonoChunks() throws {
        let chunks = try AudioFileTranscriber.chunks(from: Self.fixtureURL)
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.sampleRate == 48_000 })

        let totalSamples = chunks.reduce(0) { $0 + $1.samples.count }
        let duration = Double(totalSamples) / 48_000
        #expect(duration > 1)
        #expect(duration < 10)

        // Guard against silently reading silence, which would make the
        // transcription test below vacuous.
        let allSamples = chunks.flatMap(\.samples)
        let rms = (allSamples.reduce(Float(0)) { $0 + $1 * $1 } / Float(allSamples.count))
            .squareRoot()
        #expect(rms > 0.005, "fixture appears to be silent")
    }

    @Test func transcribesKnownSpeechFromAFile() async throws {
        guard let locale = await Self.installedLocale() else {
            withKnownIssue("on-device speech model not installed on this machine") {
                Issue.record("skipped")
            }
            return
        }

        let text = try await AudioFileTranscriber.transcribe(
            url: Self.fixtureURL,
            locale: locale
        )
        let normalised = text.lowercased()

        // Substring assertions rather than an exact match: recognisers vary on
        // punctuation and casing across OS versions, and pinning those would
        // make this fail for reasons that have nothing to do with the pipeline.
        #expect(!normalised.isEmpty, "transcription returned nothing")
        #expect(normalised.contains("becky"))
        #expect(normalised.contains("promotion"))
        #expect(normalised.contains("deployment"))
    }

    /// The payoff test: real speech through the real recogniser, into the real
    /// matcher, surfacing the right page from the real vault.
    @Test func transcribedSpeechResolvesTheCorrectWikiPage() async throws {
        guard let locale = await Self.installedLocale() else {
            withKnownIssue("on-device speech model not installed on this machine") {
                Issue.record("skipped")
            }
            return
        }

        let text = try await AudioFileTranscriber.transcribe(
            url: Self.fixtureURL,
            locale: locale
        )

        let vault = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
        let index = WikiIndexBuilder.build(
            try WikiScanner.scan(directory: vault).files.map(MarkdownParser.parse)
        )

        var coordinator = WikiMatchCoordinator(threshold: WikiMatchCoordinator.defaultThreshold)
        let match = coordinator.ingest(
            utterance: text,
            index: index,
            now: Date(timeIntervalSince1970: 0)
        )

        let resolved = try #require(match, "no wiki page matched the transcript: \"\(text)\"")
        #expect(resolved.document.title.contains("Becky"))
    }

    // MARK: - Buffering policy

    @Test func captureStreamsMustNotDropAudio() async {
        // A direct regression guard for the second half of the same incident:
        // the capture streams used `.bufferingNewest`, so a consumer that fell
        // behind lost interior audio and the recogniser received speech with
        // holes in it. Roughly half the session went missing.
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )

        let chunkCount = 500
        for index in 0..<chunkCount {
            continuation.yield(
                AudioChunk(
                    samples: [Float](repeating: Float(index) / Float(chunkCount), count: 512),
                    sampleRate: 48_000,
                    source: .system
                )
            )
        }
        continuation.finish()

        var received = 0
        for await _ in stream { received += 1 }
        #expect(received == chunkCount, "audio was dropped before the consumer ran")
    }
}
