import AppKit
import OSLog
import SwiftUI

/// Hosts the first-run wizard in a real window.
///
/// AppKit rather than a SwiftUI `Window` scene because Wikily's only declared
/// scene is `Settings`, and adding a second scene purely for something shown
/// once would put a permanent "Wikily Setup" entry in the Window menu of an app
/// that has no menu bar to put it in.
///
/// `LSUIElement` means the app is never active on its own, so this has to
/// activate explicitly — otherwise the wizard opens behind whatever the user was
/// doing, on first launch, with nothing to click to find it.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private static let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "Onboarding"
    )

    /// Held for the window's lifetime so it isn't deallocated mid-flow, and
    /// cleared on close so a second run builds a fresh one.
    private static var current: OnboardingWindowController?

    private var window: NSWindow?
    private let settings: AppSettings

    private init(settings: AppSettings) {
        self.settings = settings
    }

    /// Show the wizard only if this install has never finished it.
    ///
    /// Returns whether anything was presented, so the caller can tell a genuine
    /// first launch from an ordinary one.
    @discardableResult
    static func presentIfNeeded(settings: AppSettings = .shared) -> Bool {
        guard !isRunningTests, !settings.hasCompletedOnboarding, current == nil else {
            return false
        }
        present(settings: settings)
        return true
    }

    /// `WikilyTests` uses the app itself as its test host, so
    /// `applicationDidFinishLaunching` — and everything it builds, including the
    /// menu bar item that triggers this — runs on every `xcodebuild test`.
    /// Without this guard a test run puts a wizard on the developer's screen and
    /// marks onboarding complete in their real preferences.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Show the wizard unconditionally — the menu's "Setup Assistant" item.
    static func present(settings: AppSettings = .shared) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = OnboardingWindowController(settings: settings)
        controller.build()
        current = controller
        logger.info("Onboarding presented")
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            // No resize: the wizard is a fixed-size flow, and a resizable window
            // here just lets the user make it too small to read.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Wikily"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView(settings: settings) { [weak self] in
                self?.close()
            }
        )
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        Self.current = nil
    }

    /// Closing the window with the red button counts as finishing.
    ///
    /// Not marking it complete would re-present the wizard on every launch until
    /// the user walked it to the end, which turns a skippable flow into a modal
    /// one by attrition. Everything in it is reachable from Settings.
    func windowWillClose(_ notification: Notification) {
        settings.hasCompletedOnboarding = true
        Self.current = nil
        window = nil
    }
}
