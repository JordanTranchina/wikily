import SwiftUI

/// Settings › General: startup behaviour and the recording permission.
///
/// The permission section is here rather than buried under Audio because it is
/// the single most likely reason a new install does nothing, and a user
/// diagnosing "Wikily isn't hearing anything" opens the first tab.
@MainActor
struct GeneralSettingsView: View {

    @Bindable var settings: AppSettings

    /// Re-read on every appearance rather than observed. TCC changes happen in
    /// System Settings, in another process, with no notification to subscribe
    /// to — so the only reliable refresh is looking again when the window comes
    /// back to the front.
    @State private var permission = MicrophonePermission.status
    @State private var isRequestingPermission = false

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Launch Wikily at login", isOn: $settings.launchAtLogin)

                if let error = settings.launchAtLoginError {
                    StatusIndicator(level: .problem, text: error)
                } else if settings.launchAtLogin, LaunchAtLogin.requiresApproval {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusIndicator(
                            level: .warning,
                            text: "macOS is waiting for you to approve Wikily as a login item."
                        )
                        Button("Open Login Items…") {
                            LaunchAtLogin.openLoginItemsSettings()
                        }
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                SettingsFootnote(
                    "Wikily spends most of its time out of the way, in the menu bar. "
                        + "Starting it at login is the difference between it being there "
                        + "when a call starts and having to remember to launch it."
                )
            }

            Section("Permissions") {
                LabeledContent("Audio recording") {
                    StatusIndicator(level: permissionLevel, text: permissionText)
                }

                switch permission {
                case .granted:
                    EmptyView()
                case .notDetermined:
                    Button("Allow Audio Recording…") {
                        requestPermission()
                    }
                    .disabled(isRequestingPermission)
                case .denied:
                    Button("Open Privacy Settings…") {
                        MicrophonePermission.openSystemSettings()
                    }
                case .restricted:
                    SettingsFootnote(
                        "This Mac is managed, and audio recording has been disabled by "
                            + "whoever configured it. Wikily cannot request it."
                    )
                }
            }
        }
        .onAppear { permission = MicrophonePermission.status }
    }

    private var permissionLevel: StatusIndicator.Level {
        switch permission {
        case .granted: .ok
        case .notDetermined: .warning
        case .denied, .restricted: .problem
        }
    }

    private var permissionText: String {
        switch permission {
        case .granted:
            "Granted — Wikily can hear the call and your microphone."
        case .notDetermined:
            "Not requested yet. macOS will ask the first time you start listening."
        case .denied:
            "Denied. Wikily can't hear anything until you re-enable it."
        case .restricted:
            "Restricted by this Mac's configuration."
        }
    }

    private func requestPermission() {
        isRequestingPermission = true
        Task {
            _ = await MicrophonePermission.request()
            permission = MicrophonePermission.status
            isRequestingPermission = false
        }
    }
}
