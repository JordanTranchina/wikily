import Foundation

/// Failures that stop a call from being captured.
///
/// Kept as one type across the tap, the microphone and the session so the UI has
/// a single thing to render, with messages written for the user rather than for
/// a log.
enum CaptureError: LocalizedError, Equatable {
    case microphoneUnavailable
    case audioCapturePermissionDenied
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "No microphone is available."
        case .audioCapturePermissionDenied:
            "Wikily needs permission to record audio before it can listen to a call."
        case .alreadyRunning:
            "Wikily is already listening."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .audioCapturePermissionDenied:
            "Open System Settings › Privacy & Security › Microphone and enable Wikily."
        case .microphoneUnavailable:
            "Connect a microphone, or turn off microphone capture in Settings › Audio."
        case .alreadyRunning:
            nil
        }
    }
}
