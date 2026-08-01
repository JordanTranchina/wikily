import SwiftUI

/// Wikily — a local-first call companion.
///
/// `LSUIElement` is set in the build settings, so there is no Dock icon and no
/// main window: the app lives as a floating overlay panel plus a menu-bar item,
/// both built in `applicationDidFinishLaunching`.
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var session: CallSession?
    private var overlay: OverlayWindowController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless diagnostics: run, report, exit without building UI.
        // See CaptureDiagnostics for why these exist. Nothing below this branch
        // may create a panel or a status item — these modes are run from a
        // terminal and must stay non-interactive.
        let diagnostic: (@Sendable () async -> Void)?
        switch true {
        case CaptureDiagnostics.isProbeRequested():
            diagnostic = { await CaptureDiagnostics.probe() }
        case CaptureDiagnostics.isSpeechProbeRequested():
            diagnostic = { await CaptureDiagnostics.probeSpeech() }
        case CaptureDiagnostics.isModelInstallRequested():
            diagnostic = { await CaptureDiagnostics.installSpeechModel() }
        case ModelDiagnostics.isRequested():
            diagnostic = { await ModelDiagnostics.run() }
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
            return
        }

        startInteractive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Releases the CoreAudio aggregate device the tap installs. Skipping it
        // leaves the user's default output device reconfigured after a crash.
        guard let session, session.isListening else { return }
        Task { await session.stopListening() }
    }

    private func startInteractive() {
        let session = CallSession()
        let overlay = OverlayWindowController(session: session) { [weak self] in
            Task { await self?.stopListening() }
        }
        let menuBar = MenuBarController(session: session, overlay: overlay)

        self.session = session
        self.overlay = overlay
        self.menuBar = menuBar

        if let vaultPath = OverlayPreview.requestedVaultPath() {
            // stderr, not `print`: this process never exits on its own, and
            // stdout is block-buffered when it is not a terminal, so a `print`
            // here would sit in the buffer forever.
            fputs("menu bar item installed: \(menuBar.isInstalled)\n", stderr)
            overlay.show()
            Task { await OverlayPreview.run(session: session, vaultPath: vaultPath) }
            return
        }

        Task { await session.restorePersistedWiki() }
    }

    private func stopListening() async {
        await session?.stopListening()
        overlay?.hide()
    }
}
