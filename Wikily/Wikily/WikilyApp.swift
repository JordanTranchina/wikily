import SwiftUI

/// Wikily — a local-first call companion.
///
/// `LSUIElement` is set in the build settings, so there is no Dock icon and no
/// main window: the app lives as a floating overlay panel plus a menu-bar item.
/// Both arrive in later phases.
@main
struct WikilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A `Settings` scene is the only scene an accessory app needs to declare.
        // The real settings UI lands in Phase 6.
        Settings {
            Text("Wikily")
                .padding()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless diagnostics: run, report, exit without building UI.
        // See CaptureDiagnostics for why these exist.
        let diagnostic: (@Sendable () async -> Void)?
        switch true {
        case CaptureDiagnostics.isProbeRequested():
            diagnostic = { await CaptureDiagnostics.probe() }
        case CaptureDiagnostics.isSpeechProbeRequested():
            diagnostic = { await CaptureDiagnostics.probeSpeech() }
        case CaptureDiagnostics.isModelInstallRequested():
            diagnostic = { await CaptureDiagnostics.installSpeechModel() }
        case CaptureDiagnostics.transcribePath() != nil:
            let path = CaptureDiagnostics.transcribePath()!
            diagnostic = { await CaptureDiagnostics.transcribeFiles(at: path) }
        case CaptureDiagnostics.requestedDuration() != nil:
            let seconds = CaptureDiagnostics.requestedDuration()!
            diagnostic = { await CaptureDiagnostics.run(seconds: seconds) }
        default:
            diagnostic = nil
        }

        if let diagnostic {
            Task {
                await diagnostic()
                await MainActor.run { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
