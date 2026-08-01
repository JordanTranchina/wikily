import AVFoundation
import CoreAudio
import Foundation
import OSLog

/// Captures everything the Mac is playing — the far side of a call — using a
/// CoreAudio process tap.
///
/// Replaces `SpeakerInput` in `src-tauri/src/speaker/macos.rs`, which reached the
/// same APIs through the `cidre` Rust bindings. The shape is identical because
/// CoreAudio dictates it:
///
///  1. Create a **process tap** over all output (`CATapDescription`), which
///     yields an audio object carrying the system mix.
///  2. Create a **private aggregate device** that owns both the real output
///     device and that tap, because a tap on its own has no IO cycle to run on.
///  3. Install an IO proc on the aggregate and pull the tap's input buffers.
///
/// The Rust version hand-rolled a lock-free ring buffer and a `Waker` to bridge
/// the realtime callback into a `futures::Stream`. `AsyncStream` with a bounded
/// buffering policy does that job here, so all of that machinery is gone.
///
/// Requires macOS 14.4+ and the audio-input TCC grant. Without the grant the tap
/// is created successfully but delivers silence, which is why
/// `AudioCaptureAuthorization` is checked before starting rather than trusting
/// the `OSStatus`.
final class SystemAudioTap: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "SystemAudioTap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    /// The tap's native format, known only after the tap exists.
    private(set) var format: AVAudioFormat?

    private let ioQueue = DispatchQueue(label: "com.wikily.Wikily.system-audio-tap")

    enum TapError: LocalizedError {
        case noOutputDevice
        case outputDeviceHasNoUID
        case tapFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .noOutputDevice:
                "No audio output device is available to capture."
            case .outputDeviceHasNoUID:
                "The selected output device could not be identified."
            case .tapFormatUnavailable:
                "The system audio tap did not report an audio format."
            }
        }
    }

    deinit {
        teardown()
    }

    /// Start capturing and return a stream of mono audio chunks.
    ///
    /// - Parameter outputDeviceID: persisted device UID, or `nil`/`"default"`
    ///   to follow the system default output.
    func start(outputDeviceID: String?) throws -> AsyncStream<AudioChunk> {
        guard let outputDevice = AudioDeviceStore.resolveOutputDevice(id: outputDeviceID) else {
            throw TapError.noOutputDevice
        }
        guard let outputUID = AudioDeviceStore.uid(of: outputDevice) else {
            throw TapError.outputDeviceHasNoUID
        }

        try createTap()
        let tapUID = try tapUID()
        let format = try tapFormat()
        self.format = format

        try createAggregateDevice(outputUID: outputUID, tapUID: tapUID)

        // Unbounded, deliberately. An earlier version used
        // `.bufferingNewest(64)` on the theory that a late buffer is worth less
        // than a current one. That is wrong for transcription: dropping interior
        // audio doesn't delay the transcript, it *corrupts* it — the recogniser
        // receives speech with holes punched through it and returns fragments.
        // Buffering costs ~192 KB per second of backlog, which is a trivial
        // price next to losing half a sentence.
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )

        let sampleRate = format.sampleRate
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateDeviceID,
            ioQueue
        ) { _, inputData, _, _, _ in
            // Realtime-ish context: no locks and no logging. `monoFloatSamples`
            // allocates, which is unavoidable — the IO proc's buffers are
            // recycled on the next cycle, so the samples must be copied out
            // before this callback returns.
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inputData,
                deallocator: nil
            ) else { return }

            let samples = buffer.monoFloatSamples
            guard !samples.isEmpty else { return }

            continuation.yield(
                AudioChunk(samples: samples, sampleRate: sampleRate, source: .system)
            )
        }
        guard status == noErr, let procID else {
            teardown()
            throw CoreAudioError(status: status, operation: "create IO proc")
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            teardown()
            throw CoreAudioError(status: startStatus, operation: "start aggregate device")
        }
        isRunning = true

        continuation.onTermination = { [weak self] _ in
            self?.stop()
        }

        logger.info("System audio tap started at \(format.sampleRate, privacy: .public) Hz")
        return stream
    }

    func stop() {
        teardown()
    }

    // MARK: - Setup steps

    private func createTap() throws {
        // A mono global tap excluding nothing: everything the Mac plays, mixed
        // to one channel. Speech recognition gains nothing from stereo, and mono
        // halves the data through the whole pipeline.
        // The `__`-prefixed name is what the NS_REFINED_FOR_SWIFT initializer is
        // actually exposed as: CoreAudio ships no Swift overlay that renames it.
        let description = CATapDescription(__monoGlobalTapButExcludeProcesses: [])
        description.name = "Wikily System Audio"
        description.uuid = UUID()
        // Private: visible only to this process, so it never shows up in other
        // apps' device pickers or in Sound settings.
        description.isPrivate = true
        // Unmuted: tapping must not silence the call for the user. The whole
        // point is to listen alongside them, not instead of them.
        let muteBehavior: CATapMuteBehavior = .unmuted
        description.muteBehavior = muteBehavior

        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "create process tap")
        }
        tapID = id
    }

    private func tapUID() throws -> String {
        try AudioObject.string(
            tapID,
            AudioObject.address(kAudioTapPropertyUID),
            operation: "read tap UID"
        )
    }

    private func tapFormat() throws -> AVAudioFormat {
        let asbd: AudioStreamBasicDescription = try AudioObject.value(
            tapID,
            AudioObject.address(kAudioTapPropertyFormat),
            operation: "read tap format"
        )
        var description = asbd
        guard let format = AVAudioFormat(streamDescription: &description) else {
            throw TapError.tapFormatUnavailable
        }
        return format
    }

    private func createAggregateDevice(outputUID: String, tapUID: String) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceNameKey: "Wikily System Audio",
            // Private: never appears in Sound settings or other apps' device
            // pickers. The user should not have to see our plumbing.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // Auto-start means the tap begins delivering as soon as the
            // aggregate's IO cycle runs.
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ],
        ]

        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "create aggregate device")
        }
        aggregateDeviceID = id
    }

    // MARK: - Teardown

    /// Unwind in reverse order of creation. Every step is best-effort and
    /// independently guarded: leaking an aggregate device leaves a phantom entry
    /// in the user's audio system until reboot, so a failure part-way through
    /// must not skip the remaining cleanup.
    private func teardown() {
        if isRunning, let ioProcID {
            let status = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if status != noErr {
                logger.error("Failed to stop aggregate device: \(status, privacy: .public)")
            }
        }
        isRunning = false

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        format = nil
    }
}
