import Foundation
import Testing
@testable import Wikily

/// Covers the utterance segmentation ported from `run_vad_capture` in
/// `src-tauri/src/speaker/commands.rs`.
///
/// All input is synthesised, so these run without CoreAudio, without a
/// microphone, and without permissions. The Rust original interleaved this logic
/// with Tauri event emission, which made it untestable in practice.
struct VoiceActivityDetectorTests {

    static let sampleRate: Double = 48_000

    /// A tone loud enough to clear both the RMS and peak gates.
    static func speech(chunks: Int, config: VADConfig = .default, amplitude: Float = 0.2) -> [Float] {
        let count = chunks * config.hopSize
        return (0..<count).map { index in
            amplitude * sin(2 * .pi * 440 * Float(index) / Float(sampleRate))
        }
    }

    static func silence(chunks: Int, config: VADConfig = .default) -> [Float] {
        [Float](repeating: 0, count: chunks * config.hopSize)
    }

    private func utterances(_ events: [VADEvent]) -> [[Float]] {
        events.compactMap {
            if case .utterance(let samples, _) = $0 { return samples }
            return nil
        }
    }

    // MARK: - Segmentation

    @Test func silenceAloneProducesNoEvents() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        let events = detector.consume(Self.silence(chunks: 100))
        #expect(events.isEmpty)
    }

    @Test func speechFollowedBySilenceProducesOneUtterance() throws {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        var events = detector.consume(Self.speech(chunks: 10))
        #expect(events.contains(.speechStarted))

        events += detector.consume(Self.silence(chunks: 50))
        let produced = utterances(events)
        #expect(produced.count == 1)

        // Roughly 0.21s of speech plus the ~0.15s of trailing silence the
        // trimmer deliberately keeps, so the clip doesn't end mid-syllable.
        let duration = Double(try #require(produced.first).count) / Self.sampleRate
        #expect(duration > 0.3)
        #expect(duration < 0.45)
    }

    @Test func tooShortABurstIsDiscardedAsNoise() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        // 3 chunks is under the 7-chunk minimum: a click, not a word.
        var events = detector.consume(Self.speech(chunks: 3))
        events += detector.consume(Self.silence(chunks: 50))

        #expect(utterances(events).isEmpty)
        #expect(events.contains { if case .discarded = $0 { return true } else { return false } })
    }

    @Test func preSpeechRollIsPrependedSoWordsAreNotClipped() throws {
        var withoutPreRoll = VoiceActivityDetector(sampleRate: Self.sampleRate)
        var events = withoutPreRoll.consume(Self.speech(chunks: 10))
        events += withoutPreRoll.consume(Self.silence(chunks: 50))
        let bare = try #require(utterances(events).first)

        var withPreRoll = VoiceActivityDetector(sampleRate: Self.sampleRate)
        // Silence first, so the rolling pre-roll buffer is full when speech starts.
        var preRollEvents = withPreRoll.consume(Self.silence(chunks: 20))
        preRollEvents += withPreRoll.consume(Self.speech(chunks: 10))
        preRollEvents += withPreRoll.consume(Self.silence(chunks: 50))
        let padded = try #require(utterances(preRollEvents).first)

        // Exactly the configured pre-roll: 12 chunks of 1024 samples.
        #expect(padded.count - bare.count == VADConfig.default.preSpeechChunks * VADConfig.default.hopSize)
    }

    @Test func briefPausesDoNotSplitAnUtterance() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        // A 20-chunk pause is well under the 45-chunk threshold — a breath, not
        // the end of a sentence.
        var events = detector.consume(Self.speech(chunks: 10))
        events += detector.consume(Self.silence(chunks: 20))
        events += detector.consume(Self.speech(chunks: 10))
        events += detector.consume(Self.silence(chunks: 50))

        #expect(utterances(events).count == 1)
    }

    @Test func longPausesSplitIntoSeparateUtterances() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        var events = detector.consume(Self.speech(chunks: 10))
        events += detector.consume(Self.silence(chunks: 50))
        events += detector.consume(Self.speech(chunks: 10))
        events += detector.consume(Self.silence(chunks: 50))

        #expect(utterances(events).count == 2)
    }

    @Test func unbrokenSpeechIsForceEmittedAtTheDurationCap() {
        var config = VADConfig.default
        config.maximumUtteranceSeconds = 0.5
        var detector = VoiceActivityDetector(config: config, sampleRate: Self.sampleRate)

        // ~1.7s of continuous speech with no pause at all.
        let events = detector.consume(Self.speech(chunks: 80, config: config))
        #expect(!utterances(events).isEmpty)
    }

    @Test func flushEmitsAnUtteranceStillInProgress() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        _ = detector.consume(Self.speech(chunks: 10))
        // Capture stops mid-sentence — the audio so far must not be dropped.
        #expect(utterances(detector.flush()).count == 1)
    }

    @Test func flushEmitsNothingWhenBelowTheMinimum() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        _ = detector.consume(Self.speech(chunks: 2))
        #expect(detector.flush().isEmpty)
    }

    @Test func resetDiscardsInProgressAudio() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        _ = detector.consume(Self.speech(chunks: 10))
        detector.reset()
        #expect(detector.flush().isEmpty)
    }

    @Test func partialChunksAreBufferedUntilComplete() {
        var detector = VoiceActivityDetector(sampleRate: Self.sampleRate)
        // Feed a full chunk's worth in sub-chunk slices, as a real IO proc does.
        let audio = Self.speech(chunks: 10)
        var events: [VADEvent] = []
        for slice in stride(from: 0, to: audio.count, by: 300) {
            let end = min(slice + 300, audio.count)
            events += detector.consume(Array(audio[slice..<end]))
        }
        events += detector.consume(Self.silence(chunks: 50))
        #expect(utterances(events).count == 1)
    }

    // MARK: - Signal helpers

    @Test func noiseGateAttenuatesBelowThresholdAndLeavesSignalAlone() {
        let quiet: [Float] = [0.001, -0.001, 0.002]
        let gated = VoiceActivityDetector.applyNoiseGate(quiet, threshold: 0.003)
        for (original, result) in zip(quiet, gated) {
            #expect(abs(result) < abs(original))
            // Soft knee, not a hard cut — sign is preserved and it never zeroes.
            #expect(result.sign == original.sign)
        }

        let loud: [Float] = [0.5, -0.5]
        #expect(VoiceActivityDetector.applyNoiseGate(loud, threshold: 0.003) == loud)
    }

    @Test func normalisationBringsLevelTowardTheTarget() {
        let quiet = Self.speech(chunks: 1, amplitude: 0.02)
        let normalised = VoiceActivityDetector.normalise(quiet, targetRMS: 0.1)
        let (rms, _) = VoiceActivityDetector.metrics(normalised)
        #expect(abs(rms - 0.1) < 0.02)
    }

    @Test func normalisationClampsGainSoSilenceIsNotAmplifiedIntoNoise() {
        // RMS just above the 0.001 floor: an unclamped gain would be ~70x.
        let veryQuiet = Self.speech(chunks: 1, amplitude: 0.002)
        let normalised = VoiceActivityDetector.normalise(veryQuiet, targetRMS: 0.1)
        let (originalRMS, _) = VoiceActivityDetector.metrics(veryQuiet)
        let (resultRMS, _) = VoiceActivityDetector.metrics(normalised)
        #expect(resultRMS <= originalRMS * 10.001)
    }

    @Test func normalisationLeavesNearSilenceUntouched() {
        let silence = [Float](repeating: 0.0001, count: 1024)
        #expect(VoiceActivityDetector.normalise(silence, targetRMS: 0.1) == silence)
    }

    @Test func normalisationSoftClipsRatherThanWrapping() {
        let hot = Self.speech(chunks: 1, amplitude: 0.9)
        let normalised = VoiceActivityDetector.normalise(hot, targetRMS: 0.9)
        #expect(normalised.allSatisfy { abs($0) <= 1.0 })
    }

    @Test func metricsReportRMSAndPeak() {
        let (rms, peak) = VoiceActivityDetector.metrics([1, -1, 1, -1])
        #expect(abs(rms - 1) < 0.0001)
        #expect(abs(peak - 1) < 0.0001)
        #expect(VoiceActivityDetector.metrics([]) == (0, 0))
    }
}
