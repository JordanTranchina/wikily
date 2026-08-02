import AppKit
import OSLog
import SwiftUI

/// Owns the overlay panel: where it sits, how it grows, and when it is on screen.
///
/// Kept separate from `OverlayPanel` so the panel stays a pure configuration
/// object (easy to assert on) and all the stateful behaviour — placement,
/// resize animation, remembering where the user dragged it — lives in one place.
@MainActor
final class OverlayWindowController {

    let panel: OverlayPanel
    private let session: CallSession

    /// Set once the user drags or nudges the panel. From then on the HUD stays
    /// where they put it: re-centring it on the next suggestion would undo a
    /// deliberate choice, usually mid-sentence.
    private var userPositioned = false

    init(session: CallSession, settings: AppSettings = .shared, onStop: @escaping () -> Void) {
        self.session = session

        let initialFrame = OverlayLayout.frame(
            contentHeight: 120,
            in: Self.preferredScreenFrame()
        )
        panel = OverlayPanel(contentRect: initialFrame)

        // `weak self` on both: the hosting view is owned by the panel, which the
        // controller owns, so a strong capture would be a cycle.
        let hosting = NSHostingView(
            rootView: OverlayView(
                session: session,
                settings: settings,
                onStop: onStop,
                onHeightChange: { [weak self] height in
                    self?.applyContentHeight(height)
                }
            )
        )
        hosting.frame = NSRect(origin: .zero, size: initialFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.onNudge = { [weak self] offset in
            self?.nudge(by: offset)
        }
    }

    // MARK: - Visibility

    /// Show without taking focus.
    ///
    /// `orderFrontRegardless` rather than `makeKeyAndOrderFront` — the latter
    /// would pull focus off the call, and `regardless` is what puts the panel on
    /// screen even though Wikily is an accessory app that is never active.
    func show() {
        if !userPositioned {
            panel.setFrame(
                OverlayLayout.frame(contentHeight: panel.frame.height, in: Self.preferredScreenFrame()),
                display: false
            )
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - Geometry

    /// Resize to fit the content, anchored to the panel's top edge.
    func applyContentHeight(_ height: CGFloat, animated: Bool = true) {
        let target = OverlayLayout.resized(
            panel.frame,
            toHeight: height.rounded(.up),
            in: currentScreenFrame()
        )
        guard abs(target.height - panel.frame.height) > 0.5 else { return }

        guard animated, panel.isVisible else {
            panel.setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    func nudge(by offset: CGSize) {
        userPositioned = true
        panel.setFrame(
            OverlayLayout.nudged(panel.frame, by: offset, in: currentScreenFrame()),
            display: true
        )
    }

    /// Put the panel back at top-centre, undoing any dragging.
    func resetPosition() {
        userPositioned = false
        panel.setFrame(
            OverlayLayout.frame(contentHeight: panel.frame.height, in: Self.preferredScreenFrame()),
            display: true
        )
    }

    private func currentScreenFrame() -> CGRect {
        panel.screen?.frame ?? Self.preferredScreenFrame()
    }

    /// The display the user is most likely looking at.
    ///
    /// The screen under the pointer beats `NSScreen.main` on a multi-display
    /// setup, where "main" is whichever screen last had a key window — often not
    /// the one the call is on, since Wikily never takes key.
    private static func preferredScreenFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
