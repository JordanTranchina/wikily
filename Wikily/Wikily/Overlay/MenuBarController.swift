import AppKit
import OSLog

/// The menu-bar item.
///
/// `LSUIElement` means no Dock icon and no main window, and Wikily deliberately
/// registers no global hotkeys — that would mean asking for Accessibility, a
/// permission far broader than anything the product needs. So this is the *only*
/// way to control Wikily. That makes it a functional requirement rather than a
/// convenience: if it fails to install, the app is unreachable and the user's
/// only recourse is Force Quit, and it also means every action has to be here.
/// Nothing may be reachable only by a keystroke.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let session: CallSession
    private let overlay: OverlayWindowController
    private let settings: AppSettings
    private let statusItem: NSStatusItem

    init(
        session: CallSession,
        overlay: OverlayWindowController,
        settings: AppSettings = .shared
    ) {
        self.session = session
        self.overlay = overlay
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        // Rebuilt from session state on every open, so AppKit's automatic
        // validation has nothing to add and would only override the enablement
        // decided in `menuNeedsUpdate`.
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "Wikily"
        refreshIcon()
        observePhase()
        installWikiReloadHandler()
        settings.reconcileLaunchAtLogin()

        // Logged because this is the app's only control surface: if the status
        // item ever fails to materialise, Wikily is unreachable and the symptom
        // ("nothing happens when I launch it") gives no clue why.
        logger.info("""
            Menu bar item installed: button=\(self.statusItem.button != nil, privacy: .public) \
            visible=\(self.statusItem.isVisible, privacy: .public)
            """)

        // Deferred by one turn rather than called inline, so the status item is
        // on screen before the wizard's closing line claims it is. Skipped under
        // `--overlay-preview`, which builds a controller to check the HUD and
        // must stay non-interactive.
        if OverlayPreview.requestedVaultPath() == nil {
            Task { @MainActor in self.presentOnboardingIfNeeded() }
        }
    }

    /// Teaches `AppSettings` how to rebuild the index.
    ///
    /// Done here because this controller is the only long-lived object that
    /// holds both a `CallSession` and the settings store. It belongs in whatever
    /// assembles the app once there is one; until then, putting it anywhere else
    /// means Settings' Re-scan button silently does nothing.
    private func installWikiReloadHandler() {
        settings.wikiReloadHandler = { [weak session] path in
            guard let session else { return nil }
            await session.loadWiki(directory: path)
            // Reported from the session's own index rather than recomputed, so
            // the numbers in Settings are the numbers matching actually uses.
            return session.index.stats
        }
    }

    /// Show the first-run wizard if this install has never seen it.
    ///
    /// Driven from here rather than from the app delegate because this is the
    /// object that owns the app's control surface, and the wizard's last step
    /// points at it. Exposed so whatever assembles the app can take it over.
    func presentOnboardingIfNeeded() {
        OnboardingWindowController.presentIfNeeded(settings: settings)
    }

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "MenuBarController")

    /// Whether AppKit actually gave us something to draw into. Reported by
    /// `--overlay-preview`, since a missing status item leaves the app with no
    /// control surface at all.
    var isInstalled: Bool { statusItem.button != nil && statusItem.isVisible }

    /// Keep the icon honest whoever changed the phase — the overlay's own Stop
    /// button and `applicationWillTerminate` both bypass this controller.
    ///
    /// `withObservationTracking` fires once and has to be re-armed, hence the
    /// re-entrant call inside the change handler.
    private func observePhase() {
        withObservationTracking {
            _ = session.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshIcon()
                self.observePhase()
            }
        }
    }

    /// Rebuilt on every open rather than mutated in place, because the titles
    /// depend on session state that changes without the menu being involved.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine))
        menu.addItem(disabledItem(wikiLine))
        if let error = session.errorMessage {
            menu.addItem(disabledItem(error))
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: session.isListening ? "Stop Listening" : "Start Listening",
            action: #selector(toggleListening),
            keyEquivalent: "l"
        )
        toggle.target = self
        menu.addItem(toggle)

        let overlayItem = NSMenuItem(
            title: overlay.isVisible ? "Hide Overlay" : "Show Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        overlayItem.target = self
        menu.addItem(overlayItem)

        let reposition = NSMenuItem(
            title: "Reset Overlay Position",
            action: #selector(resetOverlayPosition),
            keyEquivalent: ""
        )
        reposition.target = self
        menu.addItem(reposition)

        menu.addItem(.separator())

        let chooseFolder = NSMenuItem(
            title: "Choose Wiki Folder…",
            action: #selector(chooseWikiFolder),
            keyEquivalent: ""
        )
        chooseFolder.target = self
        menu.addItem(chooseFolder)

        let rescan = NSMenuItem(
            title: "Re-scan Wiki",
            action: #selector(rescanWiki),
            keyEquivalent: ""
        )
        rescan.target = self
        rescan.isEnabled = settings.wikiFolderPath != nil
        menu.addItem(rescan)

        menu.addItem(.separator())

        // ⌘, is shown because it is the shortcut every Mac user reaches for, and
        // it works *while this menu is open*. It does not work globally — Wikily
        // has no menu bar of its own to route it — which is exactly why the item
        // has to exist rather than relying on the keystroke.
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let setup = NSMenuItem(
            title: "Setup Assistant…",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        setup.target = self
        menu.addItem(setup)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Wikily", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Items

    private var statusLine: String {
        switch session.phase {
        case .idle: "Not listening"
        case .starting: "Starting…"
        case .listening: "Listening"
        }
    }

    private var wikiLine: String {
        guard settings.wikiFolderPath != nil else { return "No wiki folder chosen" }
        return SettingsFormatting.count(session.index.documents.count, singular: "page")
            + " indexed"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleListening() {
        Task {
            await session.toggleListening()
            if session.isListening {
                overlay.show()
            } else {
                overlay.hide()
            }
        }
    }

    @objc private func toggleOverlay() {
        if overlay.isVisible {
            overlay.hide()
        } else {
            overlay.show()
        }
    }

    @objc private func resetOverlayPosition() {
        overlay.resetPosition()
    }

    @objc private func chooseWikiFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder holding your markdown wiki."

        // An accessory app has no active state of its own, so the open panel can
        // otherwise appear behind the call window with no way to reach it.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Through `AppSettings` rather than straight to the session, so the
        // choice is persisted and the Knowledge Base tab's stats stay truthful.
        Task { try? await settings.setWikiFolder(url.path) }
    }

    @objc private func rescanWiki() {
        Task { try? await settings.rescanWiki() }
    }

    /// Open the settings window.
    ///
    /// Not `NSApp.sendAction(showSettingsWindow:)`. That is the usual way to
    /// reach a SwiftUI `Settings` scene and it silently does nothing here — see
    /// `SettingsWindowController` for the measurement and the reason.
    @objc private func openSettings() {
        SettingsWindowController.present(settings: settings)
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.present(settings: settings)
    }

    @objc private func quit() {
        Task {
            await session.stopListening()
            NSApp.terminate(nil)
        }
    }

    private func refreshIcon() {
        let symbol = session.isListening ? "waveform.circle.fill" : "waveform.circle"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: session.isListening ? "Wikily listening" : "Wikily idle"
        )
        statusItem.button?.image?.isTemplate = true
    }
}
