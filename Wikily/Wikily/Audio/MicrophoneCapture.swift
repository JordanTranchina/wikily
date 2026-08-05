import AVFoundation
import CoreAudio
import Foundation
import OSLog

/// Captures the user's own voice from the microphone.
///
/// This has no counterpart in the Tauri build. Despite the spec describing
/// "dual-stream" capture, `src-tauri/src/speaker/` only ever taps system output;
/// `selectedAudioDevices.input` is stored in settings and never used. Wikily
/// wants both sides of a call — what the customer says *and* what the rep
/// promises — so the mic stream is added here and tagged so downstream code can
/// tell the two apart.
final class MicrophoneCapture: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "MicrophoneCapture")
    private let engine = AVAudioEngine()
    private var isRunning = false

    deinit {
        stop()
    }

    /// Start capturing and return a stream of mono audio chunks.
    ///
    /// - Parameter inputDeviceID: persisted device UID, or `nil`/`"default"` to
    ///   follow the system default input.
    func start(inputDeviceID: String?) throws -> AsyncStream<AudioChunk> {
        if let inputDeviceID, inputDeviceID != AudioDevice.systemDefaultID {
            try selectInputDevice(uid: inputDeviceID)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureError.microphoneUnavailable
        }

        // Unbounded — see the note in SystemAudioTap. Dropping interior audio
        // corrupts the transcript rather than merely delaying it.
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )

        let sampleRate = format.sampleRate
        // 0 lets AVAudioEngine pick its natural buffer size rather than forcing
        // a conversion on the audio thread.
        inputNode.installTap(onBus: 0, bufferSize: 0, format: format) { buffer, _ in
            let samples = buffer.monoFloatSamples
            guard !samples.isEmpty else { return }
            continuation.yield(
                AudioChunk(samples: samples, sampleRate: sampleRate, source: .microphone)
            )
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }
        isRunning = true

        continuation.onTermination = { [weak self] _ in
            self?.stop()
        }

        logger.info("Microphone capture started at \(sampleRate, privacy: .public) Hz")
        return stream
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    // MARK: - Device selection

    /// Point the engine's input at a specific device.
    ///
    /// `AVAudioEngine` has no device property of its own on macOS — the
    /// selection has to be pushed down to the underlying audio unit.
    private func selectInputDevice(uid: String) throws {
        guard let deviceID = AudioDeviceStore.resolveInputDevice(id: uid) else {
            // A disconnected device shouldn't fail the call; fall through to the
            // system default, same as the output path does.
            logger.warning("Input device \(uid, privacy: .public) not found; using default")
            return
        }

        var id = deviceID
        let audioUnit = engine.inputNode.audioUnit
        guard let audioUnit else { throw CaptureError.microphoneUnavailable }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "select input device")
        }
    }
}
