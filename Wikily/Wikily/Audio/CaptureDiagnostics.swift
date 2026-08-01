import AVFoundation
import Foundation
import Speech

/// Headless diagnostics for the parts of Wikily that can't be unit-tested:
/// the CoreAudio object graph, voice-activity segmentation on real speech, and
/// on-device transcription.
///
/// Everything here is opt-in via a launch argument and time-boxed. `--probe-*`
/// modes are read-only and capture nothing. `--capture-diagnostics` records, and
/// says so up front, for exactly as long as it is asked to.
enum CaptureDiagnostics {

    static let launchArgument = "--capture-diagnostics"
    static let probeArgument = "--probe-audio"
    static let speechProbeArgument = "--probe-speech"
    static let installArgument = "--install-speech-model"

    static func isProbeRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(probeArgument)
    }

    static func isSpeechProbeRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(speechProbeArgument)
    }

    static func isModelInstallRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(installArgument)
    }

    /// Parse the launch arguments. Returns the requested duration, or `nil` when
    /// this isn't a recording run.
    static func requestedDuration(from arguments: [String] = CommandLine.arguments) -> Int? {
        guard let index = arguments.firstIndex(of: launchArgument) else { return nil }
        let next = arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
        return max(1, min(next ?? 30, 300))
    }

    // MARK: - Audio probe

    /// Build the full CoreAudio object graph, report what it negotiated, tear it
    /// down. **Captures nothing and writes nothing.**
    ///
    /// The tap-plus-aggregate-device construction is the one part of the audio
    /// layer that can't be unit-tested and fails in ways an `OSStatus` doesn't
    /// explain.
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
                """)
            }
            _ = stream  // Immediately discarded; nothing is read from it.
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

    // MARK: - Speech probe

    /// Report on-device transcription availability. **Read-only.**
    static func probeSpeech() async {
        print("""

        Wikily speech probe
        ───────────────────
        """)

        guard SpeechModelInstaller.isSupported else {
            print("\nSpeechTranscriber is not available on this machine.\n")
            return
        }
        print("\nSpeechTranscriber: available")

        let installed = await SpeechTranscriber.installedLocales
        let supported = await SpeechTranscriber.supportedLocales
        print("Supported locales: \(supported.count)")
        print("Installed locales: \(installed.isEmpty ? "none" : installed.map(\.identifier).joined(separator: ", "))")

        guard let locale = await SpeechModelInstaller.resolvedLocale() else {
            print("\nNo usable locale for \(Locale.current.identifier).\n")
            return
        }
        print("Resolved locale:   \(locale.identifier)")

        switch await SpeechModelInstaller.state(for: locale) {
        case .installed:
            print("\nModel installed. Transcription will run fully offline.\n")
        case .notInstalled:
            print("""

            Model not installed yet. It downloads once, then transcription runs
            offline forever after. Install it with:

              Wikily \(installArgument)

            """)
        case .downloading:
            print("\nModel is downloading.\n")
        case .unsupported:
            print("\nOn-device transcription is unsupported for this locale.\n")
        case .failed(let message):
            print("\nModel state unknown: \(message)\n")
        }
    }

    /// Download and install the on-device speech model.
    static func installSpeechModel() async {
        guard let locale = await SpeechModelInstaller.resolvedLocale() else {
            print("\nNo supported locale to install.\n")
            return
        }

        print("""

        Installing the on-device speech model for \(locale.identifier).
        This is the only step that needs the network.

        """)

        await withCheckedContinuation { continuation in
            let finished = Locked(false)
            Task {
                await SpeechModelInstaller.install(locale: locale) { state in
                    switch state {
                    case .downloading(let fraction):
                        print(String(format: "  %.0f%%", fraction * 100))
                    case .installed:
                        print("\nInstalled. Transcription now runs fully offline.\n")
                        if finished.exchange(true) == false { continuation.resume() }
                    case .failed(let message):
                        print("\nFailed: \(message)\n")
                        if finished.exchange(true) == false { continuation.resume() }
                    case .unsupported:
                        print("\nUnsupported on this machine.\n")
                        if finished.exchange(true) == false { continuation.resume() }
                    case .notInstalled:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Recording diagnostics

    /// Capture for a fixed window, transcribe on-device, and write one WAV per
    /// detected utterance.
    ///
    /// Voice-activity detection can be tested against synthesised tones (see
    /// `VoiceActivityDetectorTests`), but whether it segments *real speech* in
    /// the right places, and whether transcription is usable, is only answerable
    /// by listening and reading.
    static func run(seconds: Int) async {
        let outputDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/wikily-utterances", isDirectory: true)

        print("""

        Wikily capture diagnostics
        ──────────────────────────
        Recording system audio and the microphone for \(seconds)s.
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
        let events: AsyncStream<CallCaptureSession.Event>
        do {
            events = try await session.start(configuration: .init())
        } catch {
            print("Capture failed to start: \(error.localizedDescription)")
            if let recovery = (error as? CaptureError)?.recoverySuggestion {
                print(recovery)
            }
            return
        }

        // Transcription is best-effort here: the WAV dump is still worth having
        // even if no model is installed.
        let (transcriber, transcriptTask) = await startTranscriber(
            sources: await session.activeSources
        )

        let collector = Task {
            var index = 0
            var totalDuration = 0.0
            for await event in events {
                switch event {
                case .audio(let chunk):
                    await transcriber?.feed(chunk)

                case .speechStarted:
                    break

                case .utterance(let utterance):
                    index += 1
                    let duration = Double(utterance.samples.count) / utterance.sampleRate
                    totalDuration += duration

                    let name = String(
                        format: "%03d-%@-%.2fs.wav",
                        index,
                        utterance.source.rawValue,
                        duration
                    )
                    do {
                        try WAVWriter.write(
                            samples: utterance.samples,
                            sampleRate: utterance.sampleRate,
                            to: outputDirectory.appendingPathComponent(name)
                        )
                        print("  [wav] \(name)")
                    } catch {
                        print("  [wav] failed: \(error.localizedDescription)")
                    }
                }
            }
            return (count: index, duration: totalDuration)
        }

        try? await Task.sleep(for: .seconds(seconds))
        await session.stop()
        await transcriber?.finish()

        // Let the last utterance and transcript drain before summarising.
        try? await Task.sleep(for: .seconds(2))
        collector.cancel()
        transcriptTask?.cancel()
        let result = await collector.value

        print("""

        ──────────────────────────
        \(result.count) utterance(s), \(String(format: "%.1f", result.duration))s of speech.
        """)
        if result.count == 0 {
            print("""

            Nothing was captured. If audio was playing, check that Wikily has
            microphone access in System Settings › Privacy & Security › Microphone.
            """)
        }
        print("")
    }

    /// Spin up on-device transcription and a task that prints its segments.
    ///
    /// Returns `(nil, nil)` when no model is installed — the WAV dump is still
    /// worth producing on its own.
    private static func startTranscriber(
        sources: [AudioChunk.Source]
    ) async -> (LiveTranscriber?, Task<Void, Never>?) {
        guard let locale = await SpeechModelInstaller.resolvedLocale(),
              await SpeechModelInstaller.state(for: locale).isReady
        else {
            print("No speech model installed — WAV dump only. Run \(installArgument) first.\n")
            return (nil, nil)
        }

        let live = LiveTranscriber(locale: locale)
        do {
            try await live.start(sources: sources)
        } catch {
            print("Transcription unavailable: \(error.localizedDescription)\n")
            return (nil, nil)
        }

        let printer = Task {
            for await segment in live.segments {
                let speaker = segment.speakerLabel
                    .padding(toLength: 5, withPad: " ", startingAt: 0)
                print("  \(speaker) │ \(segment.text)")
            }
        }
        print("Transcribing on-device (\(locale.identifier)).\n")
        return (live, printer)
    }
}

/// Minimal thread-safe flag, so a progress callback invoked from an arbitrary
/// context can resume a continuation exactly once.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func exchange(_ newValue: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
