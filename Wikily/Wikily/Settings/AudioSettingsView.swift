import SwiftUI

/// Settings › Audio: which devices Wikily listens to.
///
/// Both pickers default to "System Default" and most users should leave them
/// there. They exist for the case that actually breaks the product: a Mac with
/// several outputs where the call is playing through one that isn't the default,
/// so the tap captures silence and Wikily looks broken rather than wrong.
@MainActor
struct AudioSettingsView: View {

    @Bindable var settings: AppSettings

    /// Enumerated on appear, not observed. CoreAudio device lists change when
    /// hardware is plugged in, which is rare enough that a Refresh button is a
    /// better trade than a property listener running for the app's lifetime.
    @State private var inputs: [AudioDevice] = []
    @State private var outputs: [AudioDevice] = []

    var body: some View {
        SettingsPane {
            Section {
                Picker("Call audio from", selection: $settings.outputDeviceID) {
                    deviceRows(outputs)
                }
            } header: {
                Text("Output")
            } footer: {
                SettingsFootnote(
                    "The device the other side of the call comes out of. Wikily taps it "
                        + "without interrupting playback."
                )
            }

            Section {
                Toggle("Capture my microphone", isOn: $settings.capturesMicrophone)

                Picker("Microphone", selection: $settings.inputDeviceID) {
                    deviceRows(inputs)
                }
                .disabled(!settings.capturesMicrophone)
            } header: {
                Text("Input")
            } footer: {
                SettingsFootnote(
                    "With this off, Wikily only hears the other person. Questions you "
                        + "ask out loud won't surface anything, which is usually not "
                        + "what you want."
                )
            }

            Section {
                Button("Refresh Devices") { reload() }
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private func deviceRows(_ devices: [AudioDevice]) -> some View {
        Text(AudioDevice.systemDefault.name).tag(AudioDevice.systemDefaultID)
        ForEach(devices) { device in
            Text(device.isDefault ? "\(device.name) (current default)" : device.name)
                .tag(device.id)
        }
    }

    private func reload() {
        inputs = AudioDeviceStore.inputDevices()
        outputs = AudioDeviceStore.outputDevices()
    }
}
