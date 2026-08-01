import AVFoundation
import AppKit
import Foundation

/// The audio-recording TCC grant, as Settings needs to talk about it.
///
/// There is only one grant here even though Wikily captures from two places.
/// `SystemAudioTap` uses a CoreAudio process tap, which macOS gates on the same
/// `NSMicrophoneUsageDescription` permission as the microphone itself — so a user
/// who declines it loses the far end of the call as well as their own voice. The
/// UI says so, because "microphone" alone implies turning it off is a privacy
/// choice with no cost, and here it disables the product.
enum MicrophonePermission {

    enum Status: Equatable {
        case granted
        case denied
        /// Never asked. The prompt appears the first time a call starts.
        case notDetermined
        /// Blocked by a profile or parental controls; the user cannot grant it.
        case restricted

        var isUsable: Bool { self == .granted }
    }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        // A case added by a future OS. Reporting "not determined" is the safe
        // reading: it offers the user a request button rather than telling them
        // they are blocked when they may not be.
        @unknown default: .notDetermined
        }
    }

    /// Trigger the system prompt. Only meaningful while `.notDetermined` — once
    /// denied, macOS never prompts again and the user has to go to the pane.
    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Deep link to System Settings › Privacy & Security › Microphone.
    ///
    /// The only recovery path after a denial: an app cannot re-prompt, and
    /// leaving the user to find this pane themselves is how a broken install
    /// stays broken.
    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
