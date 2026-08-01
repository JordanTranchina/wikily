import AppKit
import OSLog
import SwiftUI

/// Owns the settings window.
///
/// **Why this is AppKit and not SwiftUI's `Settings` scene.** It was the scene
/// first. It does not work in this app: `NSApp.sendAction(showSettingsWindow:)`
/// finds a target (SwiftUI installs a stub on its own app delegate) and returns
/// `true`, and then no window is ever created — verified by dumping
/// `NSApp.windows` before and after the call, under both `.accessory` and
/// `.regular` activation policies. The cause is that Wikily declares no
/// renderable scene: its menu bar is an AppKit `NSStatusItem`, not a
/// `MenuBarExtra`, so SwiftUI's scene graph has nothing to bring up and the
/// `Settings` scene is never instantiated.
///
/// Hosting the same SwiftUI view in an `NSWindow` costs about thirty lines and
/// removes a dependency on an undocumented selector. It also matches how every
/// other window in this app is built — the overlay panel and the first-run
/// wizard are both AppKit shells around SwiftUI content.
///
/// The window still *looks* like a standard settings window: toolbar tabs, a
/// fixed width, no Save button, and ⌘W to close.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private static let logger = Logger(subsystem: "com.wikily.Wikily", category: "Settings")

    private static var current: SettingsWindowController?

    /// Remembers where the user put the window — worth doing for something they
    /// open repeatedly while setting Wikily up.
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("WikilySettingsWindow")

    private var window: NSWindow?
    private let settings: AppSettings

    private init(settings: AppSettings) {
        self.settings = settings
    }

    /// Open the window, or bring it forward if it is already up.
    static func present(settings: AppSettings = .shared) {
        // An accessory app is never active on its own, so without this the
        // window opens behind the call the user is on and there is no Dock icon
        // to click to find it.
        NSApp.activate(ignoringOtherApps: true)

        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = SettingsWindowController(settings: settings)
        controller.build()
        current = controller
        logger.info("Settings window opened")
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsRootView(settings: settings))
        // The window's size is ours, not SwiftUI's. Left on the default
        // (`.preferredContentSize`), a `TabView` of `Form`s reports an ideal
        // width of ~0 and the window opens two points wide — measured, not
        // theorised. Fixing the width also stops the window resizing itself as
        // the user moves between panes, which reads as a glitch.
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "Wikily Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(
            NSSize(width: SettingsMetrics.width, height: SettingsMetrics.height)
        )
        // Width locked, height adjustable: the panes differ enough in length
        // that a single fixed height either wastes space or clips the longest.
        window.contentMinSize = NSSize(
            width: SettingsMetrics.width,
            height: SettingsMetrics.minimumHeight
        )
        window.contentMaxSize = NSSize(width: SettingsMetrics.width, height: 1200)

        // Order matters. Centre first as the fallback, then let a saved frame
        // override it, then start autosaving. Registering the autosave name
        // *before* centring — the obvious arrangement — restores the user's
        // frame and then immediately throws it away by re-centring.
        window.center()
        window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Released on close so the next open rebuilds the view, picking up any
    /// device or permission change made while the window was shut.
    func windowWillClose(_ notification: Notification) {
        Self.current = nil
        window = nil
    }
}
