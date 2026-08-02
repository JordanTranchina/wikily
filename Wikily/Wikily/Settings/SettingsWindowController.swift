import AppKit
import OSLog
import Sparkle
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
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {

    private static let logger = Logger(subsystem: "com.wikily.Wikily", category: "Settings")

    private static var current: SettingsWindowController?

    /// Remembers where the user put the window — worth doing for something they
    /// open repeatedly while setting Wikily up.
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("WikilySettingsWindow")

    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsRootView>?
    private let settings: AppSettings
    private let updater: SPUUpdater?

    /// Which pane is showing. Persisted for the lifetime of the app rather than
    /// on disk — reopening Settings during one setup session should land where
    /// the user left off; across launches, General is the right answer again.
    private static var selectedTab: SettingsTab = .general

    private init(settings: AppSettings, updater: SPUUpdater?) {
        self.settings = settings
        self.updater = updater
    }

    /// Open the window, or bring it forward if it is already up.
    ///
    /// - Parameter updater: nil when no updater exists yet — the General pane
    ///   simply omits the "check for updates" toggle in that case, matching
    ///   how the app behaves before `WikilyApp` has finished starting up.
    static func present(settings: AppSettings = .shared, updater: SPUUpdater? = nil) {
        // An accessory app is never active on its own, so without this the
        // window opens behind the call the user is on and there is no Dock icon
        // to click to find it.
        NSApp.activate(ignoringOtherApps: true)

        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = SettingsWindowController(settings: settings, updater: updater)
        controller.build()
        current = controller
        logger.info("Settings window opened")
    }

    private func build() {
        let hosting = NSHostingController(
            rootView: SettingsRootView(settings: settings, tab: Self.selectedTab, updater: updater)
        )
        // The window's size is ours, not SwiftUI's. Left on the default
        // (`.preferredContentSize`), a `Form` reports an ideal width of ~0 and
        // the window opens two points wide — measured, not theorised. Fixing the
        // width also stops the window resizing itself as the user moves between
        // panes, which reads as a glitch.
        hosting.sizingOptions = []
        self.hosting = hosting

        let window = NSWindow(contentViewController: hosting)
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

        // `.preference` is what makes the title bar carry the tabs as icon-over-
        // label buttons, centred, with no separate backdrop — the look every
        // other Mac settings window has. It replaces the SwiftUI `TabView`,
        // whose segmented picker drew its own grey band across the chrome.
        let toolbar = NSToolbar(identifier: "WikilySettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = Self.selectedTab.itemIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        self.window = window
        applyTitle()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Tabs

    /// The pane name, not the app name.
    ///
    /// This is the convention every settings window follows, and it is load-
    /// bearing in `.preference` style: the toolbar labels are small, so the
    /// title is what tells the user which pane they are on at a glance.
    /// `self.window`, not the local — this runs after `build()` has stored it,
    /// and also from `selectTab`, where there is no local to reach for.
    private func applyTitle() {
        window?.title = Self.selectedTab.title
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(itemIdentifier: sender.itemIdentifier) else { return }
        Self.selectedTab = tab
        // The root view is replaced rather than the whole content controller, so
        // the window keeps its size and the swap doesn't flash.
        hosting?.rootView = SettingsRootView(settings: settings, tab: tab, updater: updater)
        window?.toolbar?.selectedItemIdentifier = tab.itemIdentifier
        applyTitle()
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    /// Without this the items are buttons that click and un-highlight; it is
    /// what gives the toolbar its persistent "which pane am I on" selection.
    nonisolated func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(itemIdentifier: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    /// Released on close so the next open rebuilds the view, picking up any
    /// device or permission change made while the window was shut.
    func windowWillClose(_ notification: Notification) {
        Self.current = nil
        window = nil
        hosting = nil
    }
}
