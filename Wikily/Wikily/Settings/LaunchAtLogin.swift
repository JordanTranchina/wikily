import Foundation
import OSLog
import ServiceManagement

/// The login item, via `SMAppService`.
///
/// Wrapped rather than called inline because `SMAppService` has one property
/// worth hiding: `status` distinguishes four states, only one of which
/// (`.enabled`) is "on", while `.requiresApproval` means the user has to finish
/// the job in System Settings. Collapsing that to a `Bool` at the boundary keeps
/// the branch in one place instead of at every call site.
///
/// `SMAppService.mainApp` registers the running bundle, which means this only
/// behaves during a normal launch — from a `xcodebuild test` host it will report
/// `.notFound`. That is why nothing in the test suite touches it.
enum LaunchAtLogin {

    private static let logger = Logger(subsystem: "com.wikily.Wikily", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is holding the registration pending the user's approval in
    /// System Settings › General › Login Items. Worth surfacing: from Wikily's
    /// side the call succeeded, but nothing will actually launch until they act.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        logger.info("Login item \(enabled ? "registered" : "unregistered", privacy: .public)")
    }

    /// Opens the pane where a pending registration gets approved.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The login item as an injectable pair of operations.
///
/// Exists for one reason: `SMAppService.mainApp` registers *the running bundle*.
/// A test that exercised `AppSettings.launchAtLogin` against the real thing
/// would be asking macOS to add the `xctest` runner to the user's Login Items —
/// a test suite with a side effect on the machine it runs on. `.inert` makes
/// that impossible rather than merely discouraged.
struct LaunchAtLoginControl: Sendable {

    var isEnabled: @Sendable () -> Bool
    var setEnabled: @Sendable (Bool) throws -> Void

    static let system = LaunchAtLoginControl(
        isEnabled: { LaunchAtLogin.isEnabled },
        setEnabled: LaunchAtLogin.setEnabled
    )

    /// Records nothing and touches nothing. For tests and SwiftUI previews.
    static let inert = LaunchAtLoginControl(isEnabled: { false }, setEnabled: { _ in })
}
