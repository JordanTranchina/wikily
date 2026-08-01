import AVFoundation
import Foundation

/// Transcribes an existing audio file with the same on-device pipeline used for
/// live calls.
///
/// Two uses. It closes the loop on `--capture-diagnostics`: after a recording
/// session, the saved WAVs can be re-transcribed and compared against what was
/// actually said, which turns "does transcription work?" from a judgement call
/// into a check. And it makes transcription regression-testable against fixture
/// audio, without a microphone or a live call.
enum AudioFileTranscriber {

    /// Read a WAV (or any format `AVAudioFile` opens) into mono chunks.
    ///
    /// Chunked rather than read whole so the analyzer sees the file the way it
    /// sees live capture — same code path, same buffering behaviour.
    static func chunks(
        from url: URL,
        source: AudioChunk.Source = .system,
        framesPerChunk: AVAudioFrameCount = 4096
    ) throws -> [AudioChunk] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        var chunks: [AudioChunk] = []

        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesPerChunk
            ) else { break }

            try file.read(into: buffer, frameCount: framesPerChunk)
            guard buffer.frameLength > 0 else { break }

            let samples = buffer.monoFloatSamples
            guard !samples.isEmpty else { continue }
            chunks.append(
                AudioChunk(samples: samples, sampleRate: format.sampleRate, source: source)
            )
        }

        return chunks
    }

    /// Transcribe a file and return the recognised text.
    static func transcribe(url: URL, locale: Locale, verbose: Bool = false) async throws -> String {
        let transcriber = SpeechAnalyzerTranscriber(
            locale: locale,
            source: .system,
            verbose: verbose
        )
        try await transcriber.start()

        // Collect before finishing: `finish()` flushes the tail of the audio,
        // and those segments must not be missed.
        let collector = Task {
            var parts: [String] = []
            for await segment in transcriber.segments {
                parts.append(segment.text)
            }
            return parts.joined(separator: " ")
        }

        for chunk in try chunks(from: url) {
            await transcriber.feed(chunk)
        }
        await transcriber.finish()

        return await collector.value
    }
}
