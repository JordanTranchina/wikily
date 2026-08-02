import AppKit
import SwiftUI

/// The call HUD.
///
/// A native re-cut of `src/components/WikiCard/index.tsx`, keeping that design's
/// three states — listening pill, collapsed match pill, expanded card — and its
/// information hierarchy (title, confidence, status, latest update, blocker,
/// actions).
///
/// Visual language matches the Claude Design wireframes (`Wikily Wireframes.dc.html`,
/// project `Wikily screen wireframes`) rather than the Tauri build: the brand
/// blue and the matched-page amber badge come from `OverlayTheme`, chip vs.
/// plain-text styling distinguishes page actions (Copy Status, Open Page) from
/// quick-ask questions (What should I say?, Recap), and the card's translucency
/// follows the user's Behavior-settings slider through `OverlayMaterial` rather
/// than a fixed material.
///
struct OverlayView: View {

    let session: CallSession
    let settings: AppSettings
    var onStop: () -> Void
    var onHeightChange: (CGFloat) -> Void

    @State private var isCollapsed = false
    @State private var didCopy = false

    /// Whether the ask field holds the keyboard. Tracked so Escape can hand it
    /// back to the call, and so the field can show that it has it.
    @FocusState private var isAskFocused: Bool

    private var document: WikiDocument? { session.currentMatch?.document }

    /// Says what the session is actually doing. `.starting` gets its own line
    /// because permission checks and device setup take a noticeable moment, and
    /// during it the HUD previously claimed to be listening already.
    private var listeningLine: String {
        switch session.phase {
        case .idle: "Wikily isn't listening"
        case .starting: "Starting…"
        case .listening: "Wikily is listening"
        }
    }

    private var ask: AskSession { session.askSession }

    /// `ask` is a computed property, so `$ask.draft` doesn't exist. The session
    /// owns the draft deliberately — clearing it on send belongs in one place.
    private var askDraft: Binding<String> {
        Binding(get: { ask.draft }, set: { ask.draft = $0 })
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedPill
            } else {
                expandedCard
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
        .animation(.easeOut(duration: 0.18), value: session.currentMatch)
        .animation(.easeOut(duration: 0.18), value: isCollapsed)
        .environment(\.overlayFontSize, CGFloat(settings.overlayFontSize))
    }

    // MARK: - Collapsed

    private var collapsedPill: some View {
        HStack(spacing: 8) {
            if let document {
                MatchBadge(size: 20)
                Text(document.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .help(document.title)
                if let score = session.currentMatch?.score {
                    ConfidenceBadge(score: score)
                }
            } else {
                WikilyMark(size: 20)
                Text(listeningLine)
                    .fontWeight(.medium)
                PulsingDot(isListening: session.isListening, isActive: session.isSpeechActive)
            }

            HUDIconButton("chevron.down", help: "Show") { isCollapsed = false }
            Divider().frame(height: 12)
            HUDIconButton("stop.fill", help: "Stop listening", role: .destructive, action: onStop)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OverlayMaterial.material(for: settings.overlayOpacity), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let message = session.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .hudFont(11)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let document {
                suggestion(document)
            } else {
                Text(
                    session.isListening
                        ? "Keep talking — Wikily will surface a page here when something in your wiki matches."
                        : "Wikily isn't listening. Start a session from the menu bar, and pages will appear here as you talk."
                )
                .hudFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            askSection
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

    private var header: some View {
        HStack(spacing: 7) {
            if let document {
                MatchBadge(size: 20)
                Text(document.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .help(document.title)
                if let score = session.currentMatch?.score {
                    ConfidenceBadge(score: score)
                }
            } else {
                WikilyMark(size: 20)
                Text("Wikily")
                    .fontWeight(.semibold)
                PulsingDot(isListening: session.isListening, isActive: session.isSpeechActive)
            }

            Spacer(minLength: 4)

            HUDIconButton("chevron.up", help: "Hide") { isCollapsed = true }
            Divider().frame(height: 12)
            HUDIconButton("stop.fill", help: "Stop listening", role: .destructive, action: onStop)
            if document != nil {
                HUDIconButton("xmark", help: "Dismiss suggestion") {
                    session.dismissCurrentMatch()
                }
            }
        }
    }

    @ViewBuilder
    private func suggestion(_ document: WikiDocument) -> some View {
        if let status = document.status, !status.isEmpty {
            HStack(spacing: 6) {
                Text("Status:")
                    .hudFont(10)
                    .foregroundStyle(.secondary)
                Text(status)
                    .hudFont(10, weight: .semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.1), in: Capsule())
            }
        }

        let detail = document.latestUpdate ?? document.summary
        if !detail.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(document.latestUpdate != nil ? "LATEST UPDATE" : "SUMMARY")
                    .hudFont(9, weight: .semibold)
                    .tracking(0.4)
                    .foregroundStyle(OverlayTheme.accent.opacity(0.75))
                Text(detail)
                    .hudFont(11.5, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(OverlayTheme.accent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(OverlayTheme.accent.opacity(0.22))
            )
        }

        if let blocker = document.blocker, !blocker.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Text("❝").hudFont(13, weight: .bold).foregroundStyle(.tertiary)
                Text("\(Text("Blocker: ").fontWeight(.semibold))\(blocker)")
                    .hudFont(10)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // `WrapLayout` rather than an HStack: two external links plus the two
        // fixed actions overflow 340pt often enough that clipping would be the
        // normal case, not the edge case.
        WrapLayout(spacing: 6) {
            HUDActionButton(
                title: didCopy ? "Copied" : "Copy Status",
                systemImage: didCopy ? "checkmark" : "doc.on.doc"
            ) {
                copyStatus(document)
            }

            HUDActionButton(title: "Open Page", systemImage: "doc.text") {
                NSWorkspace.shared.open(URL(fileURLWithPath: document.id))
            }

            ForEach(document.links.prefix(2), id: \.url) { link in
                HUDActionButton(title: truncated(link.label), systemImage: "arrow.up.right.square") {
                    if let url = URL(string: link.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help(link.url)
            }
        }
    }

    // MARK: - Ask Wikily

    /// Quick actions, the answer thread, and the ask field.
    ///
    /// The text field is the only control here that takes keyboard focus. The
    /// panel is `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded`, so clicking
    /// a *button* steals nothing, and only clicking into the field routes
    /// keystrokes away from the call. Escape hands them straight back — that is
    /// the whole mitigation for typing during a live call, so it matters more
    /// than it looks.
    @ViewBuilder
    private var askSection: some View {
        Divider().opacity(0.5)

        // Plain icon-and-label items with dot separators, not filled chips —
        // these are a running row of *questions to ask*, not results to act on
        // the way the page's own actions (Copy Status, Open Page) are. Keeping
        // them visually quieter is what tells them apart at a glance.
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

        HStack(spacing: 6) {
            TextField("Ask Wikily…", text: askDraft)
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

    // MARK: - Actions

    /// The copy blob from the Tauri card: title, then whichever of status,
    /// latest update and blocker exist — what a rep pastes into the call chat.
    private func copyStatus(_ document: WikiDocument) {
        var lines = [document.title]
        if let status = document.status, !status.isEmpty { lines.append("Status: \(status)") }
        if let latest = document.latestUpdate, !latest.isEmpty { lines.append("Latest: \(latest)") }
        if let blocker = document.blocker, !blocker.isEmpty { lines.append("Blocker: \(blocker)") }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    private func truncated(_ label: String) -> String {
        label.count > 18 ? label.prefix(18) + "…" : label
    }
}

// MARK: - Pieces

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

/// The amber badge shown in place of `WikilyMark` while a page is matched —
/// the wireframe's lightbulb-in-a-circle, so a glance at the collapsed pill
/// tells "idle" (blue W) from "found something" (amber bulb) without reading
/// the title next to it.
private struct MatchBadge: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "lightbulb.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(OverlayTheme.matchBadge, in: Circle())
    }
}

private struct ConfidenceBadge: View {
    var score: Double

    var body: some View {
        Text("\(Int((score * 100).rounded()))%")
            .hudFont(9, weight: .semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(OverlayTheme.accent)
            .background(OverlayTheme.accent.opacity(0.12), in: Capsule())
            .help("Match confidence")
    }
}

/// The listening indicator. Pulses continuously so a silent stretch of call
/// still reads as "running", and brightens while the VAD hears speech.
///
/// `isListening` is not decoration. This dot was green and pulsing whenever the
/// HUD was on screen, including with the session idle, so the panel asserted
/// that Wikily was hearing the call when it was not — the one thing this cue
/// exists to tell the truth about, and the reason Stop looked like it had failed.
private struct PulsingDot: View {
    var isListening: Bool
    var isActive: Bool
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(isListening ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(.green, lineWidth: 1)
                    .scaleEffect(isPulsing && isListening ? 2.2 : 1)
                    .opacity(isPulsing && isListening ? 0 : 0.7)
                    .opacity(isListening ? 1 : 0)
            }
            .opacity(isListening ? (isActive ? 1 : 0.65) : 0.5)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

/// A control circle — Stop, Hide/Show, Dismiss — matching the wireframe's
/// `.top-pill-stop`/`.ctrl`: a subtly-filled circle at rest, not a bare glyph.
/// The fill is what reads as "this is a button" at HUD scale, where a plain
/// icon with only a hover-tint is easy to miss entirely.
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

/// A bordered pill for an action with a concrete result — Copy Status, Open
/// Page, an external link. Matches the wireframe's `.chip`: outlined, not
/// filled, so it reads as a distinct affordance from the plain-text quick-ask
/// items in `HUDInlineAction`.
private struct HUDActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .hudFont(10, weight: .semibold)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isHovering ? OverlayTheme.accent.opacity(0.1) : .primary.opacity(0.03))
                )
                .overlay(Capsule().strokeBorder(.primary.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? OverlayTheme.accent : .primary)
        .onHover { isHovering = $0 }
    }
}

/// One item in the quick-ask row — icon and label only, no fill or border.
/// The wireframe's `.act-item`: these are questions to ask, not results to act
/// on, so they read quieter than `HUDActionButton`'s chips.
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
