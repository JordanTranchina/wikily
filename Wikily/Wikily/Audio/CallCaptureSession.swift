import AVFoundation
import Foundation
import OSLog

/// One call's worth of listening: starts the capture sources, runs each through
/// its own voice-activity detector, and emits a single event stream.
///
/// Replaces the coordination in `start_system_audio_capture` plus the event
/// plumbing in `useSystemAudio.ts`.
///
/// Emits raw audio *and* voice-activity events, because the two now serve
/// different consumers. `SpeechAnalyzer` wants the continuous stream — it does
/// its own endpointing, better than the VAD does, and feeding it disconnected
/// utterances would cost both accuracy and latency. The VAD survives as the
/// cheap "someone is speaking" signal that drives the overlay's live indicator,
/// and as the source of the WAV files the capture diagnostics write.
actor CallCaptureSession {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "CallCaptureSession")

    /// A complete utterance as segmented by the VAD.
    struct Utterance: Sendable, Equatable {
        var samples: [Float]
        var sampleRate: Double
        var source: AudioChunk.Source
    }

    enum Event: Sendable {
        /// Raw captured audio, for transcription.
        case audio(AudioChunk)
        /// Speech began on a source — drives the live "listening" indicator.
        case speechStarted(AudioChunk.Source)
        /// A VAD-segmented utterance, for diagnostics and WAV dumps.
        case utterance(Utterance)
    }

    struct Configuration: Sendable {
        var vad: VADConfig = .default
        /// Persisted output device UID, or `nil` for the system default.
        var outputDeviceID: String?
        /// Persisted input device UID, or `nil` for the system default.
        var inputDeviceID: String?
        /// Whether to also capture the user's own voice.
        var capturesMicrophone: Bool = true

        init(
            vad: VADConfig = .default,
            outputDeviceID: String? = nil,
            inputDeviceID: String? = nil,
            capturesMicrophone: Bool = true
        ) {
            self.vad = vad
            self.outputDeviceID = outputDeviceID
            self.inputDeviceID = inputDeviceID
            self.capturesMicrophone = capturesMicrophone
        }
    }

    private let systemTap = SystemAudioTap()
    private let microphone = MicrophoneCapture()
    private var tasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<Event>.Continuation?
    private(set) var isRunning = false
    /// Which sources actually started, so callers know how many transcribers to
    /// spin up.
    private(set) var activeSources: [AudioChunk.Source] = []

    /// Begin capturing. The returned stream finishes when `stop()` is called.
    func start(configuration: Configuration) throws -> AsyncStream<Event> {
        guard !isRunning else { throw CaptureError.alreadyRunning }

        let systemStream = try systemTap.start(outputDeviceID: configuration.outputDeviceID)
        activeSources = [.system]

        // The microphone is best-effort: losing the user's own side is a
        // degraded call, but losing the customer's side is a useless one. Never
        // let a mic failure take down the whole session.
        var microphoneStream: AsyncStream<AudioChunk>?
        if configuration.capturesMicrophone {
            do {
                microphoneStream = try microphone.start(inputDeviceID: configuration.inputDeviceID)
                activeSources.append(.microphone)
            } catch {
                logger.error("""
                    Microphone capture unavailable: \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }

        // Unbounded — see the note in SystemAudioTap. This stream carries the
        // raw audio the transcriber consumes, so a dropped element is lost
        // speech, not just a late frame.
        let (stream, continuation) = AsyncStream<Event>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.continuation = continuation
        isRunning = true

        tasks.append(
            consume(systemStream, source: .system, config: configuration.vad, into: continuation)
        )
        if let microphoneStream {
            tasks.append(
                consume(
                    microphoneStream,
                    source: .microphone,
                    config: configuration.vad,
                    into: continuation
                )
            )
        }

        return stream
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        systemTap.stop()
        microphone.stop()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        activeSources.removeAll()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Internals

    /// Drive one capture source: forward its audio, and run it through its own
    /// detector for activity events.
    ///
    /// The detector is created lazily on the first chunk because the true sample
    /// rate isn't known until audio arrives — the tap negotiates it with the
    /// hardware, and it can differ from the device's nominal rate.
    private func consume(
        _ chunks: AsyncStream<AudioChunk>,
        source: AudioChunk.Source,
        config: VADConfig,
        into continuation: AsyncStream<Event>.Continuation
    ) -> Task<Void, Never> {
        Task {
            var detector: VoiceActivityDetector?

            for await chunk in chunks {
                if Task.isCancelled { break }

                continuation.yield(.audio(chunk))

                if detector == nil {
                    detector = VoiceActivityDetector(config: config, sampleRate: chunk.sampleRate)
                }
                for event in detector!.consume(chunk.samples) {
                    switch event {
                    case .speechStarted:
                        continuation.yield(.speechStarted(chunk.source))
                    case .utterance(let samples, let sampleRate):
                        continuation.yield(
                            .utterance(
                                Utterance(
                                    samples: samples,
                                    sampleRate: sampleRate,
                                    source: chunk.source
                                )
                            )
                        )
                    case .discarded:
                        break
                    }
                }
            }

            // Don't lose a sentence that was still in progress when capture ended.
            if let final = detector?.flush() {
                for case .utterance(let samples, let sampleRate) in final {
                    continuation.yield(
                        .utterance(
                            Utterance(samples: samples, sampleRate: sampleRate, source: source)
                        )
                    )
                }
            }
        }
    }
}
