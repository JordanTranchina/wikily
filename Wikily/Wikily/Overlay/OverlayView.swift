import AppKit
import SwiftUI

/// The call HUD.
///
/// A native re-cut of the Claude Design "Floating assistant widget" wireframe
/// (`Floating Assistant Widget.dc.html`, project `Wikily screen wireframes`):
/// an always-visible toolbar (status icon, Hide/Show, Stop) with a togglable
/// assist panel below it holding the quick-action row, the Q&A thread, and the
/// ask field. `OverlayStatus` drives the toolbar's status icon — listening,
/// idle, thinking, researching, or ready — from the session's published state.
///
/// Supersedes the earlier `Wikily Wireframes.dc.html` card design, which put
/// the matched page's title/status/summary/blocker/links directly on the HUD.
/// That content has no home in this redesign yet — Jordan asked to drop it for
/// now and revisit once the toolbar+panel model is settled (so does the
/// dismiss-current-match affordance, which lived next to that title).
///
struct OverlayView: View {

    let session: CallSession
    let settings: AppSettings
    var onStop: () -> Void
    var onHeightChange: (CGFloat) -> Void

    @State private var isCollapsed = false

    /// Whether the ask field holds the keyboard. Tracked so Escape can hand it
    /// back to the call, and so the field can show that it has it.
    @FocusState private var isAskFocused: Bool

    private var ask: AskSession { session.askSession }
    private var status: OverlayStatus { OverlayStatus(session: session) }

    /// `ask` is a computed property, so `$ask.draft` doesn't exist. The session
    /// owns the draft deliberately — clearing it on send belongs in one place.
    private var askDraft: Binding<String> {
        Binding(get: { ask.draft }, set: { ask.draft = $0 })
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if !isCollapsed {
                panel
            }
        }
        .hudFont(12)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(width: OverlayLayout.width)
        // Measured at its natural height, then reported up so the panel can
        // animate to match. The outer `maxHeight` fill is what stops that
        // measurement from feeding back on itself: the panel's height must never
        // be an input to the content's height, or the two chase each other.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: status)
        .animation(.easeOut(duration: 0.18), value: isCollapsed)
        .environment(\.overlayFontSize, CGFloat(settings.overlayFontSize))
    }

    // MARK: - Toolbar

    /// The wireframe's `.fw-toolbar`: a status icon, the Hide/Show pill, and
    /// Stop, always on screen regardless of whether the panel is showing.
    private var toolbar: some View {
        HStack(spacing: 8) {
            StatusIcon(status: status, size: 28)
            HideShowButton(isCollapsed: isCollapsed) { isCollapsed.toggle() }
            Spacer(minLength: 4)
            HUDIconButton("stop.fill", help: "Stop listening", role: .destructive, action: onStop)
        }
        .padding(6)
        .background(OverlayMaterial.material(for: settings.overlayOpacity), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Assist panel

    /// The wireframe's `.fw-panel`: quick actions, the answer thread, and the
    /// ask field. Shown only while `isCollapsed` is false.
    ///
    /// The text field is the only control here that takes keyboard focus. The
    /// panel is `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded`, so clicking
    /// a *button* steals nothing, and only clicking into the field routes
    /// keystrokes away from the call. Escape hands them straight back — that is
    /// the whole mitigation for typing during a live call, so it matters more
    /// than it looks.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = session.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .hudFont(11)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Plain icon-and-label items with dot separators, not filled chips —
            // these are a running row of *questions to ask*, not results to act
            // on.
            WrapLayout(spacing: 7) {
                ForEach(Array(QuickAction.allCases.enumerated()), id: \.offset) { index, action in
                    if index > 0 {
                        Circle()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 3, height: 3)
                    }
                    HUDInlineAction(title: action.title, systemImage: action.systemImage) {
                        session.run(action)
                    }
                    .disabled(ask.isAnswering)
                }
            }

            if !ask.messages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ask.messages) { message in
                        askBubble(message)
                    }
                    if ask.isAnswering {
                        Text("Thinking…")
                            .hudFont(10)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let message = ask.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .hudFont(10)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            askInputRow
        }
        .padding(12)
        .background(
            OverlayMaterial.material(for: settings.overlayOpacity),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 4)
    }

    private var askInputRow: some View {
        HStack(spacing: 6) {
            TextField("Ask for what to say next…", text: askDraft)
                .textFieldStyle(.plain)
                .hudFont(11)
                .focused($isAskFocused)
                .onSubmit { session.submitAsk() }
                .onKeyPress(.escape) {
                    // Give the keyboard back to the call rather than making the
                    // user click away to reach their mute shortcut.
                    isAskFocused = false
                    NSApp.keyWindow?.resignKey()
                    return .handled
                }

            if ask.isAnswering {
                HUDIconButton("stop.circle", help: "Stop answering") { ask.cancel() }
            } else {
                HUDIconButton(
                    "arrow.up.circle.fill",
                    help: "Ask",
                    tint: ask.canSend ? OverlayTheme.accent : nil,
                    action: { session.submitAsk() }
                )
                .disabled(!ask.canSend)
            }

            if !ask.messages.isEmpty {
                HUDIconButton("trash", help: "Clear thread") { ask.clear() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(.primary.opacity(0.06)))
        .overlay(
            Capsule().strokeBorder(
                isAskFocused ? OverlayTheme.accent.opacity(0.6) : .primary.opacity(0.12)
            )
        )
    }

    private func askBubble(_ message: AskSession.Message) -> some View {
        HStack(alignment: .top, spacing: 5) {
            if message.role == .user {
                Spacer(minLength: 24)
                Text(message.text)
                    .hudFont(11, weight: .medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 10,
                            style: .continuous
                        )
                        .fill(OverlayTheme.accent)
                    )
                    .foregroundStyle(.white)
            } else {
                WikilyMark(size: 14)
                Text(message.text)
                    .hudFont(11)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 10,
                            bottomTrailingRadius: 10,
                            topTrailingRadius: 10,
                            style: .continuous
                        )
                        .fill(.primary.opacity(0.06))
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    // Answers get read aloud or pasted; selection is the cheapest
                    // way to let someone grab a phrase mid-call.
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Pieces

/// The brand mark, used as the assistant's chat-bubble avatar.
private struct WikilyMark: View {
    var size: CGFloat

    var body: some View {
        Text("W")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(OverlayTheme.accent, in: Circle())
    }
}

/// The toolbar's status indicator — the wireframe's five-state icon (listening,
/// idle, thinking, researching, ready). Not a control: a glance at its color
/// and glyph says what Wikily is doing right now, replacing the old pulsing-dot
/// + brand-mark pairing.
private struct StatusIcon: View {
    let status: OverlayStatus
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(fill)
            glyph
        }
        .frame(width: size, height: size)
        .help(help)
    }

    private var fill: Color {
        switch status {
        case .idle: OverlayTheme.idleStatus
        case .listening, .thinking, .researching: OverlayTheme.accent
        case .ready: OverlayTheme.matchBadge
        }
    }

    private var help: String {
        switch status {
        case .idle: "Wikily isn't listening"
        case .listening: "Wikily is listening"
        case .thinking: "Thinking…"
        case .researching: "Researching…"
        case .ready: "A page matched"
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch status {
        case .listening:
            EqualizerGlyph(size: size)
        case .idle:
            Image(systemName: "zzz")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        case .thinking:
            SpinnerGlyph(size: size)
        case .researching:
            PageFlipGlyph(size: size)
        case .ready:
            Image(systemName: "lightbulb.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Three bars pulsing at staggered offsets while Wikily is listening — the
/// wireframe's animated equalizer glyph.
private struct EqualizerGlyph: View {
    let size: CGFloat
    @State private var isTall = false

    /// Short/tall/medium, matching the wireframe's three bar lengths.
    private let relativeHeights: [CGFloat] = [0.32, 0.58, 0.44]
    private let delays: [Double] = [0, 0.15, 0.3]

    var body: some View {
        HStack(spacing: size * 0.09) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: size * 0.11, height: size * relativeHeights[index])
                    .scaleEffect(y: isTall ? 1 : 0.45, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delays[index]),
                        value: isTall
                    )
            }
        }
        .onAppear { isTall = true }
    }
}

/// A rotating arc while an answer is generating — the wireframe's spinner.
private struct SpinnerGlyph: View {
    let size: CGFloat
    @State private var isRotating = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.6)
            .stroke(.white, style: StrokeStyle(lineWidth: max(size * 0.09, 1.5), lineCap: .round))
            .frame(width: size * 0.5, height: size * 0.5)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: isRotating)
            .onAppear { isRotating = true }
    }
}

/// An open book flipping in 3D while Research runs — distinct from the generic
/// spinner so a running Research request reads differently from any other
/// in-flight ask.
private struct PageFlipGlyph: View {
    let size: CGFloat
    @State private var isFlipped = false

    var body: some View {
        Image(systemName: "book.pages")
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isFlipped)
            .onAppear { isFlipped = true }
    }
}

/// The wireframe's `.fw-hide-btn`: a pill with a chevron and a text label,
/// toggling whether the assist panel below the toolbar is shown. The chevron
/// direction matches the panel's next move — up while showing (pressing folds
/// it away), down while collapsed (pressing brings it back).
private struct HideShowButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(
                isCollapsed ? "Show" : "Hide",
                systemImage: isCollapsed ? "chevron.down" : "chevron.up"
            )
            .hudFont(11, weight: .semibold)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { isHovering = $0 }
    }
}

/// A control circle — Stop, Send, Stop-answering, Clear — matching the
/// wireframe's `.fw-circle-btn`: a subtly-filled circle at rest, not a bare
/// glyph. The fill is what reads as "this is a button" at HUD scale, where a
/// plain icon with only a hover-tint is easy to miss entirely.
private struct HUDIconButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole?
    /// Overrides the default secondary/primary tint — used for the send button,
    /// which should read as accent-colored whenever it's enabled, not only on
    /// hover.
    var tint: Color?
    let action: () -> Void

    init(
        _ symbol: String,
        help: String,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.help = help
        self.role = role
        self.tint = tint
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 21, height: 21)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var foreground: Color {
        if let tint { return tint }
        guard isHovering else { return .secondary }
        return role == .destructive ? .red : .primary
    }

    private var fill: Color {
        if isHovering {
            return role == .destructive ? Color.red.opacity(0.16) : Color.primary.opacity(0.12)
        }
        return Color.primary.opacity(0.07)
    }
}

/// One item in the quick-ask row — icon and label only, no fill or border.
/// The wireframe's `.fw-action`: these are questions to ask, not results to act
/// on, so they read quieter than a filled chip would.
private struct HUDInlineAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .hudFont(10.5, weight: .semibold)
                .labelStyle(.titleAndIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? OverlayTheme.accent : .secondary)
        .onHover { isHovering = $0 }
    }
}

/// Minimal flow layout — wraps children onto new lines instead of clipping.
///
/// Hand-rolled because the alternative, a `Grid` with a fixed column count, is
/// wrong for buttons whose widths come from their labels.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, projected > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
