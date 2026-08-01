import AppKit
import OSLog

/// The menu-bar item.
///
/// `LSUIElement` means no Dock icon and no main window, so this is currently the
/// *only* way to control Wikily. That makes it a functional requirement rather
/// than a convenience: if it fails to install, the app is unreachable and the
/// user's only recourse is Force Quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let session: CallSession
    private let overlay: OverlayWindowController
    private let statusItem: NSStatusItem

    init(session: CallSession, overlay: OverlayWindowController) {
        self.session = session
        self.overlay = overlay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Wikily"
        refreshIcon()
        observePhase()

        // Logged because this is the app's only control surface: if the status
        // item ever fails to materialise, Wikily is unreachable and the symptom
        // ("nothing happens when I launch it") gives no clue why.
        logger.info("""
            Menu bar item installed: button=\(self.statusItem.button != nil, privacy: .public) \
            visible=\(self.statusItem.isVisible, privacy: .public)
            """)
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
        guard session.wikiFolderPath != nil else { return "No wiki folder chosen" }
        let count = session.index.documents.count
        return "\(count) page\(count == 1 ? "" : "s") indexed"
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

        Task { await session.loadWiki(directory: url.path) }
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
