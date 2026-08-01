import CoreAudio
import Foundation

/// A CoreAudio call that failed, carrying the raw `OSStatus`.
struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? {
        "\(operation) failed (\(Self.describe(status)))"
    }

    /// Four-character codes read far better than their decimal form in logs.
    private static func describe(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        if bytes.allSatisfy({ (0x20...0x7e).contains($0) }) {
            return "'\(String(decoding: bytes, as: UTF8.self))'"
        }
        return String(status)
    }
}

/// Thin, type-safe wrappers over the `AudioObjectGetPropertyData` C API.
///
/// The raw calls need a correctly-sized buffer, an address struct and an
/// `inout` size on every use; these wrappers keep that boilerplate in one place
/// so the capture code reads as intent rather than as CoreAudio ceremony.
enum AudioObject {

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func hasProperty(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress
    ) -> Bool {
        var address = address
        return AudioObjectHasProperty(objectID, &address)
    }

    /// Read a fixed-size value (an `AudioObjectID`, a `Float64`, a struct).
    static func value<T>(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        as type: T.Type = T.self,
        operation: String = "read audio property"
    ) throws -> T {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }

        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: operation)
        }
        return buffer.pointee
    }

    /// Read a variable-length array property (device lists, stream lists).
    static func array<T>(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        of type: T.Type = T.self,
        operation: String = "read audio property list"
    ) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: operation)
        }
        let count = Int(size) / MemoryLayout<T>.size
        guard count > 0 else { return [] }

        var values = [T](unsafeUninitializedCapacity: count) { _, initialized in
            initialized = count
        }
        status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &values)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: operation)
        }
        return values
    }

    /// Read a `CFString` property as a Swift `String`.
    static func string(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        operation: String = "read audio string property"
    ) throws -> String {
        var address = address
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else {
            throw CoreAudioError(status: status, operation: operation)
        }
        return value as String
    }

    /// Number of buffers on a device's streams in the given scope.
    ///
    /// Zero means the device has no channels in that direction, which is how
    /// "is this an input or an output device?" is actually determined — the
    /// device list itself doesn't say.
    static func bufferCount(
        _ deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0
        else { return 0 }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        return Int(buffer.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
    }
}
