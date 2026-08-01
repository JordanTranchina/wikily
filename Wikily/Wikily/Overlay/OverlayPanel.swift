import AppKit

/// The floating HUD window.
///
/// Every setting here exists to satisfy one requirement: the user is on a call,
/// so the overlay must be visible over whatever Zoom is doing and must never take
/// focus away from it. Getting any of these wrong is a product failure rather
/// than a cosmetic one, which is why `OverlayPanelTests` asserts them.
///
/// - `.nonactivatingPanel` lets the panel receive a click without activating
///   Wikily, so clicking Dismiss does not background the call window.
/// - `.floating` keeps it above ordinary windows without entering the
///   screen-saver/status band, where it would cover system UI.
/// - `.canJoinAllSpaces` follows the user between Spaces, and
///   `.fullScreenAuxiliary` is what allows it over a full-screen app at all —
///   without it, a full-screen Zoom simply hides the overlay.
/// - `hidesOnDeactivate` defaults to `true` on `NSPanel`, which would hide the
///   HUD the moment the user clicked back into the call. It is the single most
///   important line in this file.
final class OverlayPanel: NSPanel {

    /// Arrow-key movement, forwarded to the window controller.
    var onNudge: ((CGSize) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The material and the rounded corners come from SwiftUI, so the window
        // itself has to contribute nothing — no background, no shadow, or the
        // card would sit on a grey rectangle.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // Nothing in the HUD accepts typed text, so the panel never needs to be
        // the main window. Leaving `canBecomeMain` false also keeps the app from
        // ever presenting itself as the focused one.
        becomesKeyOnlyIfNeeded = true
    }

    /// Key, but never main.
    ///
    /// Key status is what puts the panel in the responder chain for arrow-key
    /// nudging. It costs nothing in focus terms here because the controller only
    /// ever calls `orderFrontRegardless()` — the panel is never *made* key on
    /// show, and `.nonactivatingPanel` means a click on it does not activate
    /// Wikily. The practical consequence is that arrow keys reach the HUD only
    /// while Wikily happens to be the active app; dragging is the affordance that
    /// works mid-call.
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        let step = OverlayLayout.nudgeStep
        // AppKit screen coordinates are y-up, so Up is a positive dy.
        switch Int(event.keyCode) {
        case 126: onNudge?(CGSize(width: 0, height: step))
        case 125: onNudge?(CGSize(width: 0, height: -step))
        case 123: onNudge?(CGSize(width: -step, height: 0))
        case 124: onNudge?(CGSize(width: step, height: 0))
        default: super.keyDown(with: event)
        }
    }
}
