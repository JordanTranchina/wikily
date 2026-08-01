import AppKit
import Testing
@testable import Wikily

/// Pins down the two parts of the overlay that fail silently and expensively:
/// the panel's window configuration, and where it gets placed.
///
/// Neither renders anything, so neither is caught by looking at the app. A panel
/// that activates the process steals focus from the call; one without
/// `.fullScreenAuxiliary` simply vanishes behind a full-screen Zoom. Both look
/// exactly like "the overlay is fine" until someone is actually on a call.
@MainActor
struct OverlayPanelTests {

    private func makePanel() -> OverlayPanel {
        OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120))
    }

    @Test func thePanelDoesNotActivateTheAppWhenClicked() {
        let panel = makePanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        // Main status is what makes an app present itself as focused.
        #expect(!panel.canBecomeMain)
    }

    @Test func thePanelFloatsAboveOrdinaryWindows() {
        let panel = makePanel()
        #expect(panel.level == .floating)
        #expect(panel.isFloatingPanel)
    }

    @Test func thePanelFollowsTheUserAcrossSpacesAndOverFullScreenApps() {
        let panel = makePanel()
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        // Without this a full-screen Zoom hides the overlay entirely — the exact
        // call the product exists for.
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    /// `NSPanel` defaults `hidesOnDeactivate` to `true`, which would hide the HUD
    /// the instant the user clicked back into their call.
    @Test func thePanelStaysVisibleWhileAnotherAppIsActive() {
        #expect(!makePanel().hidesOnDeactivate)
    }

    @Test func thePanelIsTransparentSoTheSwiftUICardDefinesItsShape() {
        let panel = makePanel()
        #expect(!panel.isOpaque)
        #expect(!panel.hasShadow)
        #expect(panel.backgroundColor == .clear)
    }

    @Test func thePanelCanBeDragged() {
        #expect(makePanel().isMovableByWindowBackground)
    }

    @Test func showingThePanelDoesNotMakeItKey() {
        let panel = makePanel()
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        #expect(!panel.isKeyWindow)
    }

    @Test func arrowKeysNudgeInScreenCoordinates() {
        let panel = makePanel()
        var moves: [CGSize] = []
        panel.onNudge = { moves.append($0) }

        for keyCode in [126, 125, 123, 124] {  // up, down, left, right
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: UInt16(keyCode)
            ) else {
                Issue.record("Could not synthesise a key event for \(keyCode)")
                return
            }
            panel.keyDown(with: event)
        }

        let step = OverlayLayout.nudgeStep
        // AppKit's y axis points up, so Up must be a *positive* dy.
        #expect(moves == [
            CGSize(width: 0, height: step),
            CGSize(width: 0, height: -step),
            CGSize(width: -step, height: 0),
            CGSize(width: step, height: 0),
        ])
    }
}

/// The placement arithmetic, as pure geometry — no screen, no panel, no app.
struct OverlayLayoutTests {

    /// A plausible display in AppKit coordinates (origin bottom-left).
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func theOverlaySitsTopCentre() {
        let frame = OverlayLayout.frame(contentHeight: 200, in: screen)

        #expect(frame.width == OverlayLayout.width)
        #expect(frame.midX == screen.midX)
        // 54pt below the top of the display, measured to the panel's top edge.
        #expect(frame.maxY == screen.maxY - OverlayLayout.topOffset)
    }

    @Test func theOffsetIsMeasuredFromTheTopWhateverTheHeight() {
        // Explicitly `CGFloat`: an inferred `[Double]` makes each expectation a
        // mixed-type comparison, which the implicit CGFloat/Double bridging then
        // fails inside the expectation macro.
        let heights: [CGFloat] = [40, 120, 400]
        for height in heights {
            let frame = OverlayLayout.frame(contentHeight: height, in: screen)
            #expect(frame.maxY == screen.maxY - OverlayLayout.topOffset)
            #expect(frame.height == height)
        }
    }

    @Test func placementFollowsTheScreenItIsGiven() {
        // A second display to the right, at a different resolution and origin.
        let secondary = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let frame = OverlayLayout.frame(contentHeight: 150, in: secondary)

        #expect(frame.midX == secondary.midX)
        #expect(frame.maxY == secondary.maxY - OverlayLayout.topOffset)
    }

    /// Growing a card must unfold it downward. Resizing a window naively pins the
    /// bottom edge, which makes the card climb toward the menu bar instead.
    @Test func growingAnchorsTheTopEdge() {
        let start = OverlayLayout.frame(contentHeight: 100, in: screen)
        let grown = OverlayLayout.resized(start, toHeight: 260, in: screen)

        #expect(grown.maxY == start.maxY)
        #expect(grown.height == 260)
        #expect(grown.origin.x == start.origin.x)
    }

    @Test func shrinkingAlsoAnchorsTheTopEdge() {
        let start = OverlayLayout.frame(contentHeight: 260, in: screen)
        let shrunk = OverlayLayout.resized(start, toHeight: 90, in: screen)

        #expect(shrunk.maxY == start.maxY)
        #expect(shrunk.height == 90)
    }

    @Test func nudgingMovesByTheStep() {
        let start = OverlayLayout.frame(contentHeight: 120, in: screen)
        let moved = OverlayLayout.nudged(
            start,
            by: CGSize(width: -OverlayLayout.nudgeStep, height: -OverlayLayout.nudgeStep),
            in: screen
        )

        #expect(moved.origin.x == start.origin.x - OverlayLayout.nudgeStep)
        #expect(moved.origin.y == start.origin.y - OverlayLayout.nudgeStep)
    }

    @Test func nudgingCannotPushTheOverlayOutOfReach() {
        let start = OverlayLayout.frame(contentHeight: 120, in: screen)

        var frame = start
        for _ in 0..<200 {
            frame = OverlayLayout.nudged(frame, by: CGSize(width: -50, height: -50), in: screen)
        }

        // Enough of the panel must remain on screen to grab and drag back.
        #expect(frame.maxX >= screen.minX + OverlayLayout.minimumVisibleInset)
        #expect(frame.maxY >= screen.minY)
    }

    @Test func aPanelTallerThanTheScreenKeepsItsHeaderVisible() {
        // The header — title, dismiss, stop — lives at the top, so an oversized
        // card must not be clamped downward until it is off the top of the
        // display.
        let frame = OverlayLayout.frame(contentHeight: screen.height + 400, in: screen)
        #expect(frame.maxY <= screen.maxY)
        #expect(frame.maxY > screen.midY)
    }
}
