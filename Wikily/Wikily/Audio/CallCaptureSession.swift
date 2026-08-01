import AVFoundation
import Foundation
import OSLog

/// One call's worth of listening: starts the capture sources, runs each through
/// its own voice-activity detector, and emits complete utterances.
///
/// Replaces the coordination that lived in `start_system_audio_capture` plus the
/// event plumbing in `useSystemAudio.ts`. The two capture sources get separate
/// detectors deliberately — they have independent sample rates, independent
/// silence patterns, and a pause on one side means nothing about the other.
actor CallCaptureSession {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "CallCaptureSession")

    /// A complete utterance, ready to transcribe.
    struct Utterance: Sendable, Equatable {
        var samples: [Float]
        var sampleRate: Double
        var source: AudioChunk.Source
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
    private var continuation: AsyncStream<Utterance>.Continuation?
    private(set) var isRunning = false

    /// Begin capturing. The returned stream finishes when `stop()` is called.
    func start(configuration: Configuration) throws -> AsyncStream<Utterance> {
        guard !isRunning else { throw CaptureError.alreadyRunning }

        let systemStream = try systemTap.start(outputDeviceID: configuration.outputDeviceID)

        // The microphone is best-effort: losing the user's own side is a
        // degraded call, but losing the customer's side is a useless one. Never
        // let a mic failure take down the whole session.
        var microphoneStream: AsyncStream<AudioChunk>?
        if configuration.capturesMicrophone {
            do {
                microphoneStream = try microphone.start(inputDeviceID: configuration.inputDeviceID)
            } catch {
                logger.error("Microphone capture unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        let (stream, continuation) = AsyncStream<Utterance>.makeStream()
        self.continuation = continuation
        isRunning = true

        tasks.append(consume(systemStream, config: configuration.vad, into: continuation))
        if let microphoneStream {
            tasks.append(consume(microphoneStream, config: configuration.vad, into: continuation))
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
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Internals

    /// Drive one capture source through its own detector.
    ///
    /// The detector is created lazily on the first chunk because the true sample
    /// rate isn't known until audio actually arrives — the tap negotiates it with
    /// the hardware, and it can differ from the device's nominal rate.
    private func consume(
        _ chunks: AsyncStream<AudioChunk>,
        config: VADConfig,
        into continuation: AsyncStream<Utterance>.Continuation
    ) -> Task<Void, Never> {
        Task {
            var detector: VoiceActivityDetector?

            for await chunk in chunks {
                if Task.isCancelled { break }

                if detector == nil {
                    detector = VoiceActivityDetector(config: config, sampleRate: chunk.sampleRate)
                }

                for event in detector!.consume(chunk.samples) {
                    switch event {
                    case .utterance(let samples, let sampleRate):
                        continuation.yield(
                            Utterance(
                                samples: samples,
                                sampleRate: sampleRate,
                                source: chunk.source
                            )
                        )
                    case .speechStarted, .discarded:
                        // Both are UI-level signals; the overlay derives its
                        // "listening" state from the capture flag instead.
                        break
                    }
                }
            }

            // Don't lose a sentence that was still in progress when capture ended.
            if let final = detector?.flush() {
                for case .utterance(let samples, let sampleRate) in final {
                    continuation.yield(
                        Utterance(samples: samples, sampleRate: sampleRate, source: .system)
                    )
                }
            }
        }
    }
}
