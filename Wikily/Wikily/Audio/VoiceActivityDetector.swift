import Foundation

/// Tuning for the voice-activity detector.
///
/// Port of `VadConfig` in `src-tauri/src/speaker/commands.rs`. The defaults are
/// the Rust ones verbatim — they were tuned against real call audio and are the
/// difference between catching a two-word answer and firing on keyboard clicks.
struct VADConfig: Sendable, Equatable, Codable {
    /// Samples analysed per decision. Everything expressed "in chunks" below is
    /// in units of this.
    var hopSize: Int = 1024
    /// RMS above which a chunk counts as speech.
    var sensitivityRMS: Float = 0.012
    /// Peak above which a chunk counts as speech, even if RMS is low.
    var peakThreshold: Float = 0.035
    /// Consecutive silent chunks that end an utterance (~1.0s at 44.1kHz).
    var silenceChunks: Int = 45
    /// Minimum speech chunks for an utterance to be kept (~0.16s).
    var minSpeechChunks: Int = 7
    /// Audio retained from *before* speech was detected (~0.27s), so utterances
    /// don't start clipped mid-word.
    var preSpeechChunks: Int = 12
    /// Below this amplitude, samples are attenuated toward silence.
    var noiseGateThreshold: Float = 0.003
    /// Hard cap on a single utterance before it is force-emitted.
    var maximumUtteranceSeconds: Double = 30

    static let `default` = VADConfig()
}

/// What the detector observed while consuming samples.
enum VADEvent: Sendable, Equatable {
    /// Speech began. Useful for driving the "listening" indicator.
    case speechStarted
    /// A complete utterance, normalised and ready to transcribe.
    case utterance(samples: [Float], sampleRate: Double)
    /// Audio was captured but rejected — almost always background noise.
    case discarded(reason: String)
}

/// Segments a continuous sample stream into utterances.
///
/// Port of `run_vad_capture` in `src-tauri/src/speaker/commands.rs`, restructured
/// as a synchronous state machine over sample buffers so it can be tested with
/// synthesised audio and no CoreAudio at all. The original interleaved this
/// logic with Tauri event emission, which made it untestable.
struct VoiceActivityDetector: Sendable {

    var config: VADConfig
    let sampleRate: Double

    private var pending: [Float] = []
    private var preSpeech: [Float] = []
    private var speechBuffer: [Float] = []
    private var inSpeech = false
    private var silenceChunks = 0
    private var speechChunks = 0

    init(config: VADConfig = .default, sampleRate: Double) {
        self.config = config
        self.sampleRate = sampleRate
    }

    private var maximumUtteranceSamples: Int {
        Int(sampleRate * config.maximumUtteranceSeconds)
    }

    private var preSpeechCapacity: Int {
        config.preSpeechChunks * config.hopSize
    }

    /// Feed samples, get back whatever the detector concluded.
    mutating func consume(_ samples: [Float]) -> [VADEvent] {
        var events: [VADEvent] = []
        pending.append(contentsOf: samples)

        var offset = 0
        while pending.count - offset >= config.hopSize {
            let chunk = Self.applyNoiseGate(
                Array(pending[offset..<(offset + config.hopSize)]),
                threshold: config.noiseGateThreshold
            )
            offset += config.hopSize
            process(chunk: chunk, into: &events)
        }
        if offset > 0 { pending.removeFirst(offset) }

        return events
    }

    /// Force-emit whatever has been collected. Called when capture stops so a
    /// final in-progress sentence isn't silently dropped.
    mutating func flush() -> [VADEvent] {
        defer { reset() }
        guard inSpeech, speechChunks >= config.minSpeechChunks, !speechBuffer.isEmpty else {
            return []
        }
        return [
            .utterance(
                samples: Self.normalise(speechBuffer, targetRMS: 0.1),
                sampleRate: sampleRate
            )
        ]
    }

    mutating func reset() {
        pending.removeAll()
        preSpeech.removeAll()
        speechBuffer.removeAll()
        inSpeech = false
        silenceChunks = 0
        speechChunks = 0
    }

    // MARK: - State machine

    private mutating func process(chunk: [Float], into events: inout [VADEvent]) {
        let (rms, peak) = Self.metrics(chunk)
        let isSpeech = rms > config.sensitivityRMS || peak > config.peakThreshold

        if isSpeech {
            if !inSpeech {
                inSpeech = true
                speechChunks = 0
                // Prepend the rolling pre-roll so the utterance doesn't start
                // clipped part-way into the first word.
                speechBuffer.append(contentsOf: preSpeech)
                preSpeech.removeAll()
                events.append(.speechStarted)
            }

            speechChunks += 1
            speechBuffer.append(contentsOf: chunk)
            silenceChunks = 0

            // Safety valve: someone talking without pause for 30s still gets
            // transcribed rather than growing the buffer without bound.
            if speechBuffer.count > maximumUtteranceSamples {
                events.append(
                    .utterance(
                        samples: Self.normalise(speechBuffer, targetRMS: 0.1),
                        sampleRate: sampleRate
                    )
                )
                speechBuffer.removeAll()
                inSpeech = false
                speechChunks = 0
                // The Rust original leaves silenceChunks stale here. That makes
                // the *next* utterance liable to be cut short, since the counter
                // resumes from a high value the moment speech pauses. Reset it.
                silenceChunks = 0
            }
            return
        }

        guard inSpeech else {
            // Not speaking yet: keep a fixed-size rolling pre-roll.
            preSpeech.append(contentsOf: chunk)
            if preSpeech.count > preSpeechCapacity {
                preSpeech.removeFirst(preSpeech.count - preSpeechCapacity)
            }
            return
        }

        silenceChunks += 1
        // Keep collecting through the pause — natural speech has gaps, and
        // cutting at the first silent chunk would shred sentences.
        speechBuffer.append(contentsOf: chunk)

        guard silenceChunks >= config.silenceChunks else { return }

        if speechChunks >= config.minSpeechChunks, !speechBuffer.isEmpty {
            // Trim the trailing pause, but leave ~0.15s so the utterance
            // doesn't end abruptly on the last syllable.
            let silenceSamples = silenceChunks * config.hopSize
            let keepSamples = Int(sampleRate * 0.15)
            let trim = max(0, silenceSamples - keepSamples)
            if speechBuffer.count > trim {
                speechBuffer.removeLast(trim)
            }
            events.append(
                .utterance(
                    samples: Self.normalise(speechBuffer, targetRMS: 0.1),
                    sampleRate: sampleRate
                )
            )
        } else {
            events.append(.discarded(reason: "Audio too short (likely background noise)"))
        }

        speechBuffer.removeAll()
        inSpeech = false
        silenceChunks = 0
        speechChunks = 0
    }

    // MARK: - Signal helpers

    /// Soft-knee noise gate: quiet samples are attenuated rather than hard-cut,
    /// which avoids the choppy artefacts a brick-wall gate introduces.
    static func applyNoiseGate(_ samples: [Float], threshold: Float) -> [Float] {
        guard threshold > 0 else { return samples }
        let kneeRatio: Float = 3
        return samples.map { sample in
            let magnitude = abs(sample)
            guard magnitude < threshold else { return sample }
            return sample * pow(magnitude / threshold, 1 / kneeRatio)
        }
    }

    static func metrics(_ chunk: [Float]) -> (rms: Float, peak: Float) {
        guard !chunk.isEmpty else { return (0, 0) }
        var sumOfSquares: Float = 0
        var peak: Float = 0
        for sample in chunk {
            let magnitude = abs(sample)
            peak = max(peak, magnitude)
            sumOfSquares += sample * sample
        }
        return ((sumOfSquares / Float(chunk.count)).squareRoot(), peak)
    }

    /// Bring an utterance to a consistent loudness so quiet speakers transcribe
    /// as well as loud ones, with soft clipping instead of hard limiting.
    static func normalise(_ samples: [Float], targetRMS: Float) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let currentRMS = (sumOfSquares / Float(samples.count)).squareRoot()
        // Near-silence: amplifying this only raises the noise floor.
        guard currentRMS >= 0.001 else { return samples }

        let gain = min(targetRMS / currentRMS, 10)
        return samples.map { sample in
            let amplified = sample * gain
            guard abs(amplified) > 1 else { return amplified }
            return (amplified < 0 ? -1 : 1) * (1 - exp(-abs(amplified)))
        }
    }
}
