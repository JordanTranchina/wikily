import AVFoundation

/// A block of captured audio, owned and safe to hand between tasks.
///
/// Both capture sources — the system-audio tap and the microphone — emit this,
/// so everything downstream (VAD, transcription, WAV dumps) is written once
/// against one type rather than twice against two.
///
/// Mono `Float` specifically, because `AVAudioPCMBuffer` is not `Sendable`: its
/// samples live in a CoreAudio-owned buffer that is recycled on the next IO
/// cycle. Converting at the boundary makes the concurrency safety a property of
/// the type rather than something every call site has to remember.
struct AudioChunk: Sendable, Equatable {
    /// Mono samples, nominally in `-1...1`.
    var samples: [Float]
    var sampleRate: Double
    /// Which side of the conversation this came from.
    var source: Source

    enum Source: String, Sendable, Equatable, Codable {
        /// System output — the far side of the call.
        case system
        /// The microphone — the user.
        case microphone
    }

    var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}

extension AVAudioPCMBuffer {

    /// The buffer's samples as mono `Float`.
    ///
    /// Multi-channel input is averaged rather than taking channel 0, so audio
    /// panned hard to one side isn't silently lost.
    var monoFloatSamples: [Float] {
        let frames = Int(frameLength)
        guard frames > 0, let channelData = floatChannelData else { return [] }

        let channels = Int(format.channelCount)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }

        var samples = [Float](repeating: 0, count: frames)
        if format.isInterleaved {
            // Interleaved buffers expose a single pointer with a per-frame stride.
            let base = channelData[0]
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += base[frame * channels + channel]
                }
                samples[frame] = sum / Float(channels)
            }
        } else {
            // Non-interleaved buffers expose one pointer per channel.
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += channelData[channel][frame]
                }
                samples[frame] = sum / Float(channels)
            }
        }
        return samples
    }

    /// Build a buffer from mono samples, for APIs that require `AVAudioPCMBuffer`
    /// (notably `SpeechAnalyzer`).
    static func mono(from samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
