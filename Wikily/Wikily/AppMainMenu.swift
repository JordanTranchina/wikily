import AppKit

/// The application menu bar.
///
/// Wikily was `LSUIElement` until it gained a Dock icon, and an accessory app
/// has no menu bar at all — which is why this file did not exist. A regular app
/// without one still launches, but it launches *wrong*: the menu bar shows only
/// the Apple menu, and because the Edit menu is what carries the standard text
/// bindings, ⌘C/⌘V/⌘A stop working in the HUD's ask field and in every text
/// field in Settings. None of those are things this app implements; they are
/// things AppKit routes through `NSMenu`.
///
/// Built in code rather than as a `MainMenu.xib` because everything else in this
/// app is built in code, and because the two items that matter — Settings and
/// Setup Assistant — have to reach objects the delegate owns.
@MainActor
enum AppMainMenu {

    /// How many top-level items a correctly-built menu has: the app menu,
    /// Edit, Session, Window, and Help. Used to detect corruption — see
    /// `guardAgainstSwiftUIReplacingTheMenu`.
    private static let expectedTopLevelItemCount = 5

    /// Retains the action target for the lifetime of the app. The menu itself
    /// holds only a weak `target`, so without this the closures die immediately
    /// and every item greys out.
    private static var actions: Actions?

    /// Retained so `guardAgainstSwiftUIReplacingTheMenu` can rebuild the
    /// Session menu identically to how `install` first built it.
    private static var menuBar: MenuBarController?

    /// Retains the key-window observer for the lifetime of the app — see
    /// `guardAgainstSwiftUIReplacingTheMenu`.
    private static var menuGuardToken: NSObjectProtocol?

    /// - Parameter menuBar: supplies the Session menu's items, so the menu bar and
    ///   the status-bar menu can never drift apart.
    static func install(
        menuBar: MenuBarController,
        openSettings: @escaping () -> Void,
        openOnboarding: @escaping () -> Void
    ) {
        let actions = Actions(openSettings: openSettings, openOnboarding: openOnboarding)
        Self.actions = actions
        Self.menuBar = menuBar

        NSApp.mainMenu = buildMainMenu(actions: actions, menuBar: menuBar)
        guardAgainstSwiftUIReplacingTheMenu()
    }

    private static func buildMainMenu(actions: Actions, menuBar: MenuBarController) -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu(actions))
        main.addItem(editMenu())
        main.addItem(sessionMenu(menuBar))
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        return main
    }

    /// SwiftUI's AppKit bridge silently strips `NSApp.mainMenu` down to its
    /// own bare-bones default — clearing our items from the *same* `NSMenu`
    /// instance and adding a single "View" item holding nothing but the OS's
    /// auto-added Full Screen toggle — the moment a window hosting SwiftUI
    /// content (the overlay panel's `NSHostingView`) takes key status. It does
    /// this even though `WikilyApp` declares no `Scene` at all, and there is
    /// no supported way to opt out: the overlay's ask field genuinely needs
    /// real key status to accept typing, so losing key status is not an
    /// option either.
    ///
    /// Because it mutates the existing object rather than swapping in a new
    /// one, an identity check (`NSApp.mainMenu !== ourMenu`) never catches
    /// it — `NSApp.mainMenu` *is* `ourMenu`, just emptied out. Checking the
    /// item count instead, and rebuilding a fresh `NSMenu` when it's short,
    /// sidesteps that: it doesn't matter why SwiftUI thinks the menu needs
    /// replacing, only that the replacement doesn't stick. The rebuild is
    /// hopped onto a fresh MainActor `Task` rather than done inline, because
    /// SwiftUI's own mutation happens around the same notification pass;
    /// reacting synchronously here can still lose the race.
    private static func guardAgainstSwiftUIReplacingTheMenu() {
        menuGuardToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard let actions, let menuBar else { return }
                guard (NSApp.mainMenu?.numberOfItems ?? 0) < expectedTopLevelItemCount else { return }
                NSApp.mainMenu = buildMainMenu(actions: actions, menuBar: menuBar)
            }
        }
    }

    // MARK: - Menus

    private static func appMenu(_ actions: Actions) -> NSMenuItem {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu()

        menu.addItem(
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        )
        menu.addItem(.separator())

        menu.addItem(
            item("Settings…", #selector(Actions.openSettings), key: ",", target: actions)
        )
        menu.addItem(
            item("Setup Assistant…", #selector(Actions.openOnboarding), target: actions)
        )
        menu.addItem(.separator())

        let services = NSMenu()
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), key: "h"))

        let hideOthers = item(
            "Hide Others",
            #selector(NSApplication.hideOtherApplications(_:)),
            key: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), key: "q"))

        return submenu(titled: name, menu)
    }

    /// The reason this file exists. Every item here is an AppKit responder-chain
    /// selector — supplying the menu is the whole implementation.
    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")

        menu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        let redo = item("Redo", Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))

        return submenu(titled: "Edit", menu)
    }

    /// Start/Stop Listening and the wiki commands.
    ///
    /// Populated by `MenuBarController` on open rather than built here: the
    /// titles depend on live session state ("Start" vs "Stop"), and having two
    /// hand-written copies of the same menu is how they end up disagreeing.
    private static func sessionMenu(_ menuBar: MenuBarController) -> NSMenuItem {
        let menu = NSMenu(title: "Session")
        menu.delegate = menuBar
        menu.autoenablesItems = false
        // Populated once up front so the items exist before the menu is first
        // opened — key equivalents are matched against the built menu, so ⌘L
        // would otherwise do nothing until the user had opened the menu by hand.
        menuBar.populateSessionItems(into: menu)
        return submenu(titled: "Session", menu)
    }

    private static func windowMenu() -> NSMenuItem {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        )
        menu.addItem(.separator())

        // Wikily has no main window, so this is the menu a user reaches for when
        // Settings or the setup wizard is what's in front — the app menu's own
        // Quit is a whole different top-level menu away. No key equivalent: ⌘Q
        // already belongs to the app menu's Quit, and giving the same shortcut
        // to two items in different top-level menus is what produces AppKit's
        // "ambiguous key equivalent" warning.
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:))))

        let windowItem = submenu(titled: "Window", menu)
        // Assigned so AppKit keeps the open-window list in this menu itself.
        NSApp.windowsMenu = menu
        return windowItem
    }

    private static func helpMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        let item = submenu(titled: "Help", menu)
        NSApp.helpMenu = menu
        return item
    }

    // MARK: - Building blocks

    private static func item(
        _ title: String,
        _ action: Selector?,
        key: String = "",
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // Left nil for the responder-chain items on purpose: a nil target is
        // what makes AppKit walk the chain and enable Cut/Copy/Paste only when
        // something can actually perform them.
        if let target { item.target = target }
        return item
    }

    private static func submenu(titled title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Bridges the menu's Obj-C target/action to the delegate's closures.
    @MainActor
    private final class Actions: NSObject {
        private let openSettingsHandler: () -> Void
        private let openOnboardingHandler: () -> Void

        init(openSettings: @escaping () -> Void, openOnboarding: @escaping () -> Void) {
            self.openSettingsHandler = openSettings
            self.openOnboardingHandler = openOnboarding
        }

        @objc func openSettings() { openSettingsHandler() }
        @objc func openOnboarding() { openOnboardingHandler() }
    }
}
