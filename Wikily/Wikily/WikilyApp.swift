import OSLog
import SwiftUI

/// Wikily — a local-first call companion.
///
/// A regular app: it has a Dock icon and a menu bar, *and* a status-bar item.
/// What it does not have is a main window — the product surface is the floating
/// overlay panel, with Settings and the setup wizard as ordinary windows opened
/// on demand. Everything is built in `applicationDidFinishLaunching`.
///
/// It was `LSUIElement` until the Dock icon was asked for. That mattered in more
/// places than it looks: an accessory app has no menu bar (see `AppMainMenu`),
/// never becomes active on its own (hence the `NSApp.activate` calls before
/// opening a window), and cannot be reached at all if the status item fails to
/// install. Only the first of those is fixed by the Dock icon.
@main
struct WikilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Deliberately empty.
        //
        // A SwiftUI `Settings` scene does not work in this app: Wikily declares
        // no renderable scene (the menu bar is an AppKit `NSStatusItem`, not a
        // `MenuBarExtra`), so the scene graph never instantiates and
        // `showSettingsWindow:` finds a target, returns true, and creates no
        // window. Settings is hosted in an AppKit window instead — see
        // `SettingsWindowController` — matching how the overlay and the
        // onboarding wizard are already built.
        //
        // Everything is assembled in `AppDelegate.applicationDidFinishLaunching`.
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
        case ModelDiagnostics.askVaultPath() != nil:
            let vault = ModelDiagnostics.askVaultPath()!
            diagnostic = { await ModelDiagnostics.probeAsk(vaultPath: vault) }
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
            // The app is no longer `LSUIElement`, so without this every headless
            // probe run from a terminal would bounce a Dock icon and steal the
            // menu bar for the second or two it takes to finish.
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await diagnostic()
                await MainActor.run { NSApplication.shared.terminate(nil) }
            }
            return
        }

        guard !reconcileWithOtherInstances() else { return }
        startInteractive()
    }

    /// Reconcile with any other running copy of Wikily.
    ///
    /// Nothing stops a second copy from launching — running from Xcode while an
    /// installed build is up does it every time — and two copies are genuinely
    /// confusing rather than merely untidy: there are two status items that look
    /// identical, two HUDs stacked pixel-on-pixel, and two audio taps.
    ///
    /// The two configurations want opposite answers to "which one survives":
    ///
    /// - **Debug** — the newest build wins and force-quits every older copy.
    ///   Handing over to whichever instance happened to answer first is exactly
    ///   backwards for iteration: a build from three Runs ago that hung mid
    ///   launch (AppKit's event loop looks perfectly idle from outside; only an
    ///   AppleEvent or a `sample` stack trace shows nothing ever reached
    ///   `applicationDidFinishLaunching`) would otherwise keep winning forever,
    ///   with every subsequent Run silently handing off to it and quitting
    ///   itself — the exact failure this replaces.
    /// - **Release** — the *original* wins and this copy quits, handing over
    ///   rather than replacing it. That direction is the safe one for a real
    ///   user: the running copy may be mid-call, and force-killing it would
    ///   drop that call with no warning. Nothing about a second launch in
    ///   production means the first one went stale the way a Debug rebuild
    ///   does.
    private func reconcileWithOtherInstances() -> Bool {
        // The unit tests' `TEST_HOST` is Wikily.app itself, so with a copy of
        // Wikily running this would quit the test runner before it could connect
        // — which surfaces as "Early unexpected exit … before establishing
        // connection", a message that names nothing to do with instances.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }

        let logger = Logger(subsystem: "com.wikily.Wikily", category: "AppDelegate")

        #if DEBUG
        for other in others {
            logger.error("""
                Force-quitting a stale Wikily instance (pid \
                \(other.processIdentifier, privacy: .public)) so this build can take over.
                """)
            // `terminate()` only asks — exactly the request that just hung for
            // the instance this replaces. `forceTerminate()` is what actually
            // guarantees it is gone before this instance stands up its own
            // status item and overlay.
            other.forceTerminate()
        }
        return false
        #else
        guard let original = others.first else { return false }
        logger.error("""
            Wikily is already running (pid \(original.processIdentifier, privacy: .public)); \
            handing over and quitting this copy.
            """)
        original.activate()
        NSApp.terminate(nil)
        return true
        #endif
    }

    /// Wikily has no main window, so closing Settings must not quit the app —
    /// the whole point is that it keeps listening while nothing is on screen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with nothing open.
    ///
    /// The default behaviour for an app with no windows is to do nothing at all,
    /// which reads as the icon being dead. Showing the overlay is the closest
    /// thing Wikily has to "the app", and it is what the click is asking for.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows else { return true }
        overlay?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Releases the CoreAudio aggregate device the tap installs. Skipping it
        // leaves the user's default output device reconfigured after a crash.
        guard let session, session.isListening else { return }
        Task { await session.stopListening() }
    }

    private func startInteractive() {
        // Settings seeds the session rather than the session reading `.shared`
        // internally, so a session can be built in a test without touching the
        // real user's preferences.
        let settings = AppSettings.shared
        let session = CallSession(coordinator: settings.matchCoordinator)
        session.captureConfiguration = settings.captureConfiguration

        let overlay = OverlayWindowController(session: session, settings: settings) { [weak self] in
            Task { await self?.stopListening() }
        }
        let menuBar = MenuBarController(session: session, overlay: overlay)

        self.session = session
        self.overlay = overlay
        self.menuBar = menuBar

        AppMainMenu.install(
            menuBar: menuBar,
            openSettings: { SettingsWindowController.present(settings: settings) },
            openOnboarding: { OnboardingWindowController.present(settings: settings) }
        )

        if let vaultPath = OverlayPreview.requestedVaultPath() {
            // stderr, not `print`: this process never exits on its own, and
            // stdout is block-buffered when it is not a terminal, so a `print`
            // here would sit in the buffer forever.
            fputs("menu bar item installed: \(menuBar.isInstalled)\n", stderr)
            overlay.show()
            Task { await OverlayPreview.run(session: session, vaultPath: vaultPath) }
            return
        }

        Task { await session.restorePersistedWiki(settings: settings) }
    }

    private func stopListening() async {
        await session?.stopListening()
        overlay?.hide()
    }
}
