import SwiftUI

/// Visual constants shared across the HUD, pulled from the Claude Design
/// wireframes (project `Wikily screen wireframes`: `Wikily Wireframes.dc.html`
/// for the original card design, `Floating Assistant Widget.dc.html` for the
/// toolbar/status-icon redesign) rather than invented to taste — the goal is
/// that the built HUD and the mockups read as the same product.
enum OverlayTheme {

    /// The wireframe's `--accent`. Deliberately not `Color.accentColor`: that
    /// tracks the user's system accent color preference, which would make
    /// Wikily's brand color whatever green or red someone has chosen in General
    /// settings — fine for a system control, wrong for a logo.
    static let accent = Color(red: 0x34 / 255, green: 0x57 / 255, blue: 0xd5 / 255)

    /// The status icon's "ready" color (`#FFB81D`) — a page is matched and
    /// waiting. From the "Floating assistant widget" wireframe
    /// (`Floating Assistant Widget.dc.html`); supersedes the earlier
    /// `Wikily Wireframes.dc.html` badge amber (`#e0a83f`) when that redesign
    /// shipped.
    static let matchBadge = Color(red: 0xff / 255, green: 0xb8 / 255, blue: 0x1d / 255)

    /// The status icon's "idle" gray — approximates the wireframe's
    /// `oklch(55% 0.02 260)`, a near-neutral gray with a faint cool cast.
    static let idleStatus = Color(red: 0x6e / 255, green: 0x71 / 255, blue: 0x80 / 255)

    /// The header/title point size the HUD's other text sizes (9–14pt) were
    /// originally designed relative to. `AppSettings.overlayFontSize` is a
    /// concrete point size the user picks — 12, 14, 16pt — for *that* label;
    /// every other `hudFont` call scales by the ratio between the two, so
    /// choosing "14" grows the whole HUD proportionally rather than just the
    /// title.
    static let referenceFontSize: CGFloat = 12
}

/// Maps the user's overlay-transparency setting to a native `Material`.
///
/// The wireframe expresses transparency as two named fills — "glass" (near-
/// opaque) and "transparent" (mostly see-through) — with literal `rgba`/`blur`
/// values baked in for a static web canvas. Reproducing those exact pixels
/// would fight the platform: macOS `Material` already gives correct vibrancy in
/// both light and dark mode, and a fixed color would not. Snapping the user's
/// continuous slider to the five system `Material` stops is the native
/// equivalent of the wireframe's slider — more transparent or more solid — with
/// none of the color hand-tuning the literal CSS would need per appearance.
enum OverlayMaterial {

    static func material(for opacity: Double) -> Material {
        switch Int((min(max(opacity, 0), 1) * 4).rounded()) {
        case 0: .ultraThinMaterial
        case 1: .thinMaterial
        case 2: .regularMaterial
        case 3: .thickMaterial
        default: .ultraThickMaterial
        }
    }
}

// MARK: - Text scale

/// The user's overlay text-size preference (`AppSettings.overlayFontSize`, a
/// concrete point size, not a multiplier), threaded through the environment
/// rather than a parameter so every label nested under `OverlayView` —
/// including the small button pieces declared beside it — can read it without
/// a size parameter added to each of them.
private struct OverlayFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = OverlayTheme.referenceFontSize
}

extension EnvironmentValues {
    var overlayFontSize: CGFloat {
        get { self[OverlayFontSizeKey.self] }
        set { self[OverlayFontSizeKey.self] = newValue }
    }
}

/// Scales `size` by how far the user's chosen point size sits from the
/// reference the HUD was designed at, so picking "14" grows every label
/// proportionally rather than overriding each one to a flat 14pt.
private struct HUDFontModifier: ViewModifier {
    @Environment(\.overlayFontSize) private var overlayFontSize
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        let ratio = overlayFontSize / OverlayTheme.referenceFontSize
        content.font(.system(size: size * ratio, weight: weight))
    }
}

extension View {
    /// A HUD text size that scales with the user's overlay text-size setting.
    /// Use for anything the user reads as content — titles, status, quick
    /// actions, chat bubbles. Fixed-size glyphs inside a fixed circle (the
    /// icon buttons, the brand mark) intentionally stay off this and keep
    /// their literal size, since scaling the glyph without the circle would
    /// just misalign it.
    func hudFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(HUDFontModifier(size: size, weight: weight))
    }
}
