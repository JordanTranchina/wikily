import Foundation

/// Writes mono `Float` samples to a 16-bit PCM WAV file.
///
/// Port of `samples_to_wav_b64` in `src-tauri/src/speaker/commands.rs`, minus the
/// base64 step — that only existed to move audio across the Rust-to-JavaScript
/// bridge, which no longer exists.
///
/// Used by the capture diagnostics to make segmentation audible: a WAV per
/// utterance is the only practical way to confirm the VAD is cutting in the
/// right places on real speech.
enum WAVWriter {

    enum WriteError: LocalizedError {
        case invalidSampleRate(Double)
        case emptyBuffer

        var errorDescription: String? {
            switch self {
            case .invalidSampleRate(let rate):
                "Invalid sample rate \(rate); expected 8000–96000 Hz."
            case .emptyBuffer:
                "Refusing to write an empty audio buffer."
            }
        }
    }

    static func data(samples: [Float], sampleRate: Double) throws -> Data {
        guard (8_000...96_000).contains(sampleRate) else {
            throw WriteError.invalidSampleRate(sampleRate)
        }
        guard !samples.isEmpty else { throw WriteError.emptyBuffer }

        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let rate = UInt32(sampleRate)
        let byteRate = rate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataBytes = UInt32(samples.count * 2)

        var data = Data(capacity: 44 + Int(dataBytes))

        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))          // PCM chunk size
        data.appendLittleEndian(UInt16(1))           // PCM format
        data.appendLittleEndian(channels)
        data.appendLittleEndian(rate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)

        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(dataBytes)

        for sample in samples {
            // Clamp before scaling: an out-of-range float would otherwise wrap
            // to the opposite polarity and sound like a click.
            let clamped = max(-1, min(1, sample))
            data.appendLittleEndian(Int16(clamped * Float(Int16.max)))
        }

        return data
    }

    static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        try data(samples: samples, sampleRate: sampleRate).write(to: url)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        // Explicitly the global `Swift.withUnsafeBytes(of:_:)`; unqualified, it
        // resolves to Data's own instance method of the same name.
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
