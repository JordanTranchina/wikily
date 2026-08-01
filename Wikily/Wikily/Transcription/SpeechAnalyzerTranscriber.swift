import AVFoundation
import Foundation
import OSLog
import Speech

/// On-device streaming transcription for one audio source.
///
/// This is the piece the Tauri build never delivered. `transcribe.rs` shelled out
/// to a whisper.cpp sidecar that wasn't in the default bundle, so the "local
/// transcription" the spec leads with returned `LOCAL_TRANSCRIPTION_UNAVAILABLE`
/// and silently fell back to a cloud API — the opposite of the product's promise.
/// `SpeechAnalyzer` makes it a first-class capability with nothing to bundle.
///
/// **Streaming, not per-utterance.** The Tauri pipeline waited for the VAD to
/// close an utterance (~1s of silence), encoded it to a WAV, and sent that off
/// to be transcribed as an isolated island of audio. Feeding `SpeechAnalyzer` a
/// continuous stream instead is both lower-latency and more accurate, because
/// the model sees running context rather than disconnected fragments. The VAD
/// remains, but as the "someone is speaking" signal for the HUD rather than as
/// the segmenter — the analyzer does its own endpointing, and it is better at it.
///
/// One instance per source: `SpeechAnalyzer` consumes a single input sequence,
/// so the system tap and the microphone each get their own. That is also what
/// gives speaker attribution for free.
actor SpeechAnalyzerTranscriber: TranscriptionService {

    private let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "SpeechAnalyzerTranscriber"
    )

    private let locale: Locale
    private let source: AudioChunk.Source

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Format the analyzer wants, and the converter that gets us there from the
    /// capture format.
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?

    private let segmentStream: AsyncStream<TranscriptSegment>
    private let segmentContinuation: AsyncStream<TranscriptSegment>.Continuation

    nonisolated let segments: AsyncStream<TranscriptSegment>

    enum TranscriberError: LocalizedError {
        case modelNotInstalled(Locale)
        case noCompatibleAudioFormat

        var errorDescription: String? {
            switch self {
            case .modelNotInstalled(let locale):
                "The on-device speech model for \(locale.identifier) isn't installed yet."
            case .noCompatibleAudioFormat:
                "No audio format compatible with on-device transcription is available."
            }
        }
    }

    init(locale: Locale, source: AudioChunk.Source, verbose: Bool = false) {
        self.locale = locale
        self.source = source
        self.verbose = verbose
        let (stream, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        self.segmentStream = stream
        self.segmentContinuation = continuation
        self.segments = stream
    }

    func start() async throws {
        guard await SpeechModelInstaller.state(for: locale).isReady else {
            throw TranscriberError.modelNotInstalled(locale)
        }

        // `.transcription` yields finalised results only. Volatile partials are
        // available via `.progressiveTranscription` and would suit a live-caption
        // view, but the wiki matcher wants settled text — re-matching on every
        // partial would make the overlay thrash.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        self.transcriber = transcriber

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw TranscriberError.noCompatibleAudioFormat
        }
        analyzerFormat = format

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        // Start consuming results *before* the analyzer, and off the actor.
        // Both matter: results delivered before anyone is iterating are lost,
        // and running the loop on this actor would make it contend with feed().
        let continuation = segmentContinuation
        let source = self.source
        let verbose = self.verbose
        resultsTask = Task.detached {
            await Self.consumeResults(
                from: transcriber,
                source: source,
                into: continuation,
                verbose: verbose
            )
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputStream)

        logger.info("""
            Transcriber started for \(self.source.rawValue, privacy: .public) \
            at \(format.sampleRate, privacy: .public) Hz
            """)
    }

    /// Instrumentation for the offline diagnostics; off in normal operation.
    private let verbose: Bool
    private var fedBuffers = 0

    func feed(_ chunk: AudioChunk) async {
        guard let inputContinuation, let analyzerFormat else {
            if verbose { print("    [debug] feed dropped: no continuation/format") }
            return
        }
        guard let buffer = converted(chunk, to: analyzerFormat) else {
            if verbose { print("    [debug] conversion returned nil") }
            return
        }
        if verbose {
            fedBuffers += 1
            if fedBuffers <= 3 {
                let inRMS = (chunk.samples.reduce(0) { $0 + $1 * $1 } / Float(chunk.samples.count))
                    .squareRoot()
                var outRMS = 0.0
                if let int16 = buffer.int16ChannelData {
                    let n = Int(buffer.frameLength)
                    var sum = 0.0
                    for i in 0..<n {
                        let v = Double(int16[0][i]) / 32768
                        sum += v * v
                    }
                    outRMS = (sum / Double(n)).squareRoot()
                }
                print("    [debug] fed buffer \(fedBuffers): in=\(chunk.samples.count) "
                    + "rms=\(String(format: "%.4f", inRMS)) -> out=\(buffer.frameLength) "
                    + "rms=\(String(format: "%.4f", outRMS)) @\(buffer.format.sampleRate)Hz")
            }
        }

        // No `bufferStartTime`. Supplying one derived from the capture sample
        // rate, while the buffer itself has been resampled to the analyzer's
        // rate, makes SpeechAnalyzer discard every input — silently, with no
        // error and an empty transcript. Letting it infer timing from the
        // buffer sequence is both correct and simpler. Segment times then come
        // from `result.range`, relative to when this transcriber started.
        inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async {
        inputContinuation?.finish()
        inputContinuation = nil

        // Flush whatever is mid-recognition rather than dropping the last
        // sentence of the call.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()

        // Await the results task rather than cancelling it. Finalising is what
        // *produces* the last results; cancelling here threw them away, which
        // silently emptied the transcript.
        await resultsTask?.value
        resultsTask = nil

        analyzer = nil
        transcriber = nil
        converter = nil
        captureFormat = nil
        segmentContinuation.finish()
    }

    // MARK: - Internals

    /// Drain the transcriber's results into the segment stream.
    ///
    /// `static` and off-actor deliberately — see the note in `start()`.
    private static func consumeResults(
        from transcriber: SpeechTranscriber,
        source: AudioChunk.Source,
        into continuation: AsyncStream<TranscriptSegment>.Continuation,
        verbose: Bool
    ) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmed
                if verbose {
                    print("    [debug] result: \"\(text)\" @\(result.range.start.seconds)")
                }
                guard !text.isEmpty else { continue }
                continuation.yield(
                    TranscriptSegment(
                        text: text,
                        source: source,
                        startTime: result.range.start.seconds
                    )
                )
            }
        } catch {
            Logger(subsystem: "com.wikily.Wikily", category: "SpeechAnalyzerTranscriber")
                .error("Transcription stream failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Convert a captured chunk into the analyzer's preferred format.
    ///
    /// The converter is built once and reused — creating one per buffer would
    /// dominate the cost of the conversion itself.
    private func converted(_ chunk: AudioChunk, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: chunk.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        // Already in the analyzer's format — skip the converter entirely.
        if sourceFormat == target {
            return AVAudioPCMBuffer.mono(from: chunk.samples, sampleRate: chunk.sampleRate)
        }

        // Built once and reused: constructing a converter per buffer would cost
        // far more than the conversion itself.
        if converter == nil || captureFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: target)
            captureFormat = sourceFormat
        }
        guard let converter else { return nil }

        // Capacity scales with the sample-rate ratio, plus slack for the
        // resampler's filter delay.
        let ratio = target.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(chunk.samples.count) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity),
              let input = AVAudioPCMBuffer.mono(
                from: chunk.samples,
                sampleRate: chunk.sampleRate
              )
        else { return nil }

        // The input buffer is handed to the block and never touched again here,
        // which is what lets region-based isolation accept it. The box exists
        // because the block is an Obj-C block the compiler must assume can run
        // later, even though `convert` calls it synchronously.
        let pending = PendingInput(input)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            guard let buffer = pending.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }

        if let conversionError {
            logger.error("Audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }
}

/// Single-use holder for a buffer handed to `AVAudioConverter`.
///
/// `@unchecked Sendable` is sound here specifically because
/// `AVAudioConverter.convert(to:error:withInputFrom:)` invokes its block
/// synchronously on the calling thread: there is no concurrent access to guard
/// against, only a block signature the compiler must treat conservatively.
private final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    /// Returns the buffer once, then `nil` — signalling end-of-input to the
    /// converter rather than looping on the same samples forever.
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
