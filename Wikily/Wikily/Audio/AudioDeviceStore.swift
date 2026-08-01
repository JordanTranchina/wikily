import CoreAudio
import Foundation

/// An audio device the user can pick in Settings → Audio.
struct AudioDevice: Sendable, Equatable, Identifiable, Hashable {
    /// The device UID — stable across reboots and reconnects, unlike the
    /// `AudioObjectID`, so this is what gets persisted.
    var id: String
    var name: String
    var isDefault: Bool

    /// Sentinel meaning "whatever the system default is right now".
    static let systemDefaultID = "default"

    static let systemDefault = AudioDevice(
        id: systemDefaultID,
        name: "System Default",
        isDefault: true
    )
}

/// Enumerates CoreAudio input and output devices.
///
/// Port of `get_input_devices` / `get_output_devices` in
/// `src-tauri/src/speaker/macos.rs`.
enum AudioDeviceStore {

    static func inputDevices() -> [AudioDevice] {
        devices(scope: kAudioObjectPropertyScopeInput)
    }

    static func outputDevices() -> [AudioDevice] {
        devices(scope: kAudioObjectPropertyScopeOutput)
    }

    /// Resolve a stored device id to a live `AudioObjectID`.
    ///
    /// Returns the system default when the id is the default sentinel, empty, or
    /// names a device that is no longer connected — unplugging headphones should
    /// not break capture.
    static func resolveOutputDevice(id: String?) -> AudioObjectID? {
        guard let id, !id.isEmpty, id != AudioDevice.systemDefaultID else {
            return defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
        if let match = deviceIDs().first(where: {
            AudioObject.bufferCount($0, scope: kAudioObjectPropertyScopeOutput) > 0
                && uid(of: $0) == id
        }) {
            return match
        }
        return defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// Resolve a stored input device UID to a live `AudioObjectID`.
    ///
    /// Returns `nil` when the device is no longer connected, so callers can fall
    /// back to the system default rather than failing.
    static func resolveInputDevice(id: String?) -> AudioObjectID? {
        guard let id, !id.isEmpty, id != AudioDevice.systemDefaultID else { return nil }
        return deviceIDs().first {
            AudioObject.bufferCount($0, scope: kAudioObjectPropertyScopeInput) > 0
                && uid(of: $0) == id
        }
    }

    static func uid(of deviceID: AudioObjectID) -> String? {
        try? AudioObject.string(
            deviceID,
            AudioObject.address(kAudioDevicePropertyDeviceUID),
            operation: "read device UID"
        )
    }

    static func name(of deviceID: AudioObjectID) -> String {
        (try? AudioObject.string(
            deviceID,
            AudioObject.address(kAudioObjectPropertyName),
            operation: "read device name"
        )) ?? "Unknown Device"
    }

    /// The device's current sample rate, needed to configure downstream format
    /// conversion.
    static func nominalSampleRate(of deviceID: AudioObjectID) -> Double? {
        try? AudioObject.value(
            deviceID,
            AudioObject.address(kAudioDevicePropertyNominalSampleRate),
            as: Float64.self,
            operation: "read device sample rate"
        )
    }

    // MARK: - Internals

    private static func deviceIDs() -> [AudioObjectID] {
        (try? AudioObject.array(
            AudioObjectID(kAudioObjectSystemObject),
            AudioObject.address(kAudioHardwarePropertyDevices),
            of: AudioObjectID.self,
            operation: "list audio devices"
        )) ?? []
    }

    private static func defaultDevice(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectID? {
        let id = try? AudioObject.value(
            AudioObjectID(kAudioObjectSystemObject),
            AudioObject.address(selector),
            as: AudioObjectID.self,
            operation: "read default device"
        )
        return id == kAudioObjectUnknown ? nil : id
    }

    private static func devices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        let defaultSelector = scope == kAudioObjectPropertyScopeInput
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        let defaultUID = defaultDevice(selector: defaultSelector).flatMap(uid(of:))

        var seen = Set<String>()
        var result: [AudioDevice] = []

        for deviceID in deviceIDs() {
            guard AudioObject.bufferCount(deviceID, scope: scope) > 0 else { continue }
            guard let uid = uid(of: deviceID), seen.insert(uid).inserted else { continue }
            result.append(
                AudioDevice(id: uid, name: name(of: deviceID), isDefault: uid == defaultUID)
            )
        }

        // Devices come back in driver-registration order, which is arbitrary and
        // shifts as hardware is plugged in. Sort so the picker is stable.
        result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }
}
