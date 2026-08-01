import CoreGraphics

/// Where the overlay sits, as pure geometry.
///
/// Split out from the window controller so the placement rules can be tested
/// without a screen, a panel, or a running app — the arithmetic is the part that
/// silently regresses (an overlay half off-screen, or drifting down as it grows).
///
/// All rectangles are in AppKit screen coordinates: origin bottom-left, `maxY`
/// at the top of the display.
enum OverlayLayout {

    /// Fixed width, matching the Tauri build's 320pt card plus its window margin.
    /// Fixed rather than proportional because a call HUD that changes width
    /// between a pill and a card reads as a layout bug, not as responsiveness.
    static let width: CGFloat = 360

    /// Gap between the top of the display and the top of the panel.
    ///
    /// 54pt is inherited from the Tauri build, where it cleared that window's own
    /// compact bar. It survives here because it also clears the menu bar on every
    /// current Mac, including notched displays, so the HUD never renders beneath
    /// it.
    static let topOffset: CGFloat = 54

    /// Distance an arrow-key press moves the panel.
    static let nudgeStep: CGFloat = 20

    /// Keep this much of the panel on screen when clamping, so a nudge can always
    /// be reversed.
    static let minimumVisibleInset: CGFloat = 40

    /// Top-centre placement on a given display.
    static func frame(
        contentHeight: CGFloat,
        in screen: CGRect,
        width: CGFloat = width
    ) -> CGRect {
        let height = max(contentHeight, 1)
        let origin = CGPoint(
            x: (screen.midX - width / 2).rounded(),
            y: (screen.maxY - topOffset - height).rounded()
        )
        return clamped(CGRect(origin: origin, size: CGSize(width: width, height: height)), in: screen)
    }

    /// Grow or shrink about the panel's *top* edge.
    ///
    /// Windows are positioned by their bottom-left corner, so the naive resize
    /// pins the bottom and makes the card climb toward the menu bar as content
    /// arrives. Anchoring the top is what makes growth read as the card
    /// unfolding downward.
    static func resized(_ frame: CGRect, toHeight height: CGFloat, in screen: CGRect) -> CGRect {
        let newHeight = max(height, 1)
        let resized = CGRect(
            x: frame.origin.x,
            y: frame.maxY - newHeight,
            width: frame.width,
            height: newHeight
        )
        return clamped(resized, in: screen)
    }

    static func nudged(_ frame: CGRect, by offset: CGSize, in screen: CGRect) -> CGRect {
        clamped(frame.offsetBy(dx: offset.width, dy: offset.height), in: screen)
    }

    /// Pull a frame back until enough of it is reachable to drag or nudge again.
    ///
    /// Deliberately not "fully inside": a panel taller than the display would
    /// otherwise be forced to the bottom, hiding the header the user needs.
    static func clamped(_ frame: CGRect, in screen: CGRect) -> CGRect {
        var result = frame
        let visible = min(minimumVisibleInset, frame.width)

        result.origin.x = min(max(result.origin.x, screen.minX - frame.width + visible), screen.maxX - visible)

        // Vertically the top edge is what has to stay reachable, since that is
        // where the header and the drag area live.
        let highestTop = screen.maxY
        let lowestTop = screen.minY + min(minimumVisibleInset, frame.height)
        let top = min(max(result.maxY, lowestTop), highestTop)
        result.origin.y = top - frame.height

        return result
    }
}
