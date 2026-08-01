import AVFoundation
import Foundation

/// A headless capture run that writes each detected utterance to a WAV file.
///
/// This is the Phase 2 verification gate. Voice-activity detection can be tested
/// against synthesised tones (see `VoiceActivityDetectorTests`), but whether it
/// segments *real speech* in the right places is only answerable by listening.
/// So: capture for a fixed window, write one WAV per utterance, print a summary.
///
/// Invoked with `--capture-diagnostics [seconds]`, which the app checks at
/// launch before building any UI. Deliberately explicit and time-boxed — it
/// records only when a person asks it to, only for as long as they specify, and
/// says exactly where the audio landed.
enum CaptureDiagnostics {

    static let launchArgument = "--capture-diagnostics"
    static let probeArgument = "--probe-audio"

    static func isProbeRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(probeArgument)
    }

    /// Build the full CoreAudio object graph, report what it negotiated, tear it
    /// down. **Captures nothing and writes nothing.**
    ///
    /// The tap-plus-aggregate-device construction is the one part of this layer
    /// that can't be unit-tested and fails in ways an `OSStatus` doesn't
    /// explain. This proves the graph is correct without recording anything.
    static func probe() async {
        print("""

        Wikily audio probe
        ──────────────────
        Building the CoreAudio object graph. No audio is captured or written.

        """)

        print("Output devices:")
        for device in AudioDeviceStore.outputDevices() {
            print("  \(device.isDefault ? "*" : " ") \(device.name)")
        }
        print("\nInput devices:")
        for device in AudioDeviceStore.inputDevices() {
            print("  \(device.isDefault ? "*" : " ") \(device.name)")
        }

        let tap = SystemAudioTap()
        do {
            let stream = try tap.start(outputDeviceID: nil)
            if let format = tap.format {
                print("""

                Process tap created.
                  sample rate: \(format.sampleRate) Hz
                  channels:    \(format.channelCount)
                  format:      \(format.commonFormat.rawValue)
                """)
            }
            // Immediately discard the stream; nothing is read from it.
            _ = stream
            tap.stop()
            print("\nTeardown clean. Audio capture is wired up correctly.\n")
        } catch {
            print("\nFailed: \(error.localizedDescription)")
            if let recovery = (error as? CaptureError)?.recoverySuggestion {
                print(recovery)
            }
            print("")
        }
    }

    /// Parse the launch arguments. Returns the requested duration, or `nil` when
    /// this isn't a diagnostics run.
    static func requestedDuration(from arguments: [String] = CommandLine.arguments) -> Int? {
        guard let index = arguments.firstIndex(of: launchArgument) else { return nil }
        let next = arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
        return max(1, min(next ?? 30, 300))
    }

    static func run(seconds: Int) async {
        let outputDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/wikily-utterances", isDirectory: true)

        print("""

        Wikily capture diagnostics
        ──────────────────────────
        Listening to system audio and the microphone for \(seconds)s.
        Play a video or join a call now.

        Utterances will be written to:
          \(outputDirectory.path)

        """)

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            print("Could not create the output directory: \(error.localizedDescription)")
            return
        }

        let session = CallCaptureSession()
        let stream: AsyncStream<CallCaptureSession.Utterance>
        do {
            stream = try await session.start(configuration: .init())
        } catch {
            print("Capture failed to start: \(error.localizedDescription)")
            if let recovery = (error as? CaptureError)?.recoverySuggestion {
                print(recovery)
            }
            return
        }

        let collector = Task {
            var index = 0
            var totalDuration = 0.0
            for await utterance in stream {
                index += 1
                let duration = Double(utterance.samples.count) / utterance.sampleRate
                totalDuration += duration

                let name = String(
                    format: "%03d-%@-%.2fs.wav",
                    index,
                    utterance.source.rawValue,
                    duration
                )
                let url = outputDirectory.appendingPathComponent(name)
                do {
                    try WAVWriter.write(
                        samples: utterance.samples,
                        sampleRate: utterance.sampleRate,
                        to: url
                    )
                    print(String(
                        format: "  [%3d] %-10@  %6.2fs  %6.0f Hz  ->  %@",
                        index,
                        utterance.source.rawValue as NSString,
                        duration,
                        utterance.sampleRate,
                        name as NSString
                    ))
                } catch {
                    print("  [\(index)] failed to write: \(error.localizedDescription)")
                }
            }
            return (count: index, duration: totalDuration)
        }

        try? await Task.sleep(for: .seconds(seconds))
        await session.stop()

        // Let the last utterance drain before summarising.
        try? await Task.sleep(for: .milliseconds(500))
        collector.cancel()
        let result = await collector.value

        print("""

        ──────────────────────────
        \(result.count) utterance(s), \(String(format: "%.1f", result.duration))s of speech.
        \(result.count == 0 ? "\nNothing was captured. If audio was playing, check that Wikily has\nmicrophone access in System Settings › Privacy & Security › Microphone.\n" : "")
        """)
    }
}
