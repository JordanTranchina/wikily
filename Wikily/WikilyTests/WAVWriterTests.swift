import AVFoundation
import Foundation
import Testing
@testable import Wikily

/// The WAV files these produce are the Phase 2 verification artefact, so a
/// malformed header would quietly invalidate the whole gate. These assert the
/// bytes directly *and* round-trip through the system decoder.
struct WAVWriterTests {

    private func tone(count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * sin(2 * .pi * 440 * Float($0) / 48_000) }
    }

    @Test func writesAWellFormedHeader() throws {
        let samples = tone(count: 1_000)
        let data = try WAVWriter.data(samples: samples, sampleRate: 48_000)

        #expect(data.count == 44 + samples.count * 2)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[12..<16], as: UTF8.self) == "fmt ")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")

        // Mono, 16-bit, 48 kHz.
        #expect(data[22] == 1)
        #expect(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self) } == 48_000)
        #expect(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 34, as: UInt16.self) } == 16)
    }

    @Test func decodesBackWithTheSystemDecoder() throws {
        let samples = tone(count: 4_800)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wikily-wav-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try WAVWriter.write(samples: samples, sampleRate: 48_000, to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length == Int64(samples.count))
    }

    @Test func clampsRatherThanWrappingOnOutOfRangeSamples() throws {
        // Without clamping, +1.5 would wrap to a large negative value and click.
        let data = try WAVWriter.data(samples: [1.5, -1.5], sampleRate: 16_000)
        let first = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 44, as: Int16.self) }
        let second = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 46, as: Int16.self) }
        #expect(first == Int16.max)
        #expect(second == -Int16.max)
    }

    @Test func rejectsEmptyBuffersAndImplausibleSampleRates() {
        #expect(throws: WAVWriter.WriteError.self) {
            try WAVWriter.data(samples: [], sampleRate: 48_000)
        }
        #expect(throws: WAVWriter.WriteError.self) {
            try WAVWriter.data(samples: [0.1], sampleRate: 500)
        }
        #expect(throws: WAVWriter.WriteError.self) {
            try WAVWriter.data(samples: [0.1], sampleRate: 192_000)
        }
    }

    @Test func diagnosticsDurationIsParsedAndBounded() {
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily"]) == nil)
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily", "--capture-diagnostics"]) == 30)
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily", "--capture-diagnostics", "45"]) == 45)
        // Bounded, so a typo can't start a ten-hour recording.
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily", "--capture-diagnostics", "99999"]) == 300)
        #expect(CaptureDiagnostics.requestedDuration(from: ["Wikily", "--capture-diagnostics", "0"]) == 1)
    }
}
