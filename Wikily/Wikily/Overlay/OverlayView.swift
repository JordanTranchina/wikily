import AppKit
import SwiftUI

/// The call HUD.
///
/// A native re-cut of `src/components/WikiCard/index.tsx`, keeping that design's
/// three states — listening pill, collapsed match pill, expanded card — and its
/// information hierarchy (title, confidence, status, latest update, blocker,
/// actions). What is deliberately *not* carried over is the AI Q&A half: the
/// thread, quick actions and the ask field all belong to a cloud-model feature
/// this build does not have, and a text field would force the panel to take
/// keyboard focus mid-call.
///
/// A live transcript strip replaces them, which is the more honest use of the
/// space: it shows the user what Wikily is actually hearing, so a call with no
/// suggestions still reads as working rather than broken.
struct OverlayView: View {

    let session: CallSession
    var onStop: () -> Void
    var onHeightChange: (CGFloat) -> Void

    @State private var isCollapsed = false
    @State private var didCopy = false

    /// Whether the ask field holds the keyboard. Tracked so Escape can hand it
    /// back to the call, and so the field can show that it has it.
    @FocusState private var isAskFocused: Bool

    private var document: WikiDocument? { session.currentMatch?.document }

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
        .font(.system(size: 12))
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
    }

    // MARK: - Collapsed

    private var collapsedPill: some View {
        HStack(spacing: 8) {
            if let document {
                WikilyMark(size: 16)
                Text(document.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .help(document.title)
                if let score = session.currentMatch?.score {
                    ConfidenceBadge(score: score)
                }
            } else {
                PulsingDot(isActive: session.isSpeechActive)
                Text("Wikily is listening")
                    .fontWeight(.medium)
            }

            HUDIconButton("chevron.down", help: "Show") { isCollapsed = false }
            Divider().frame(height: 12)
            HUDIconButton("stop.fill", help: "Stop listening", role: .destructive, action: onStop)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
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
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let document {
                suggestion(document)
            } else {
                Text("Keep talking — Wikily will surface a page here when something in your wiki matches.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            transcriptStrip
            askSection
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let document {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(document.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .help(document.title)
                if let score = session.currentMatch?.score {
                    ConfidenceBadge(score: score)
                }
            } else {
                WikilyMark(size: 16)
                Text("Wikily")
                    .fontWeight(.semibold)
                PulsingDot(isActive: session.isSpeechActive)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.1), in: Capsule())
            }
        }

        let detail = document.latestUpdate ?? document.summary
        if !detail.isEmpty {
            Text(detail)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }

        if let blocker = document.blocker, !blocker.isEmpty {
            Text("**Blocker:** \(blocker)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Transcript

    private var transcriptStrip: some View {
        let recent = session.transcript.suffix(4)
        return VStack(alignment: .leading, spacing: 3) {
            Divider().opacity(0.5)
            if recent.isEmpty {
                Text(session.isListening ? "Listening…" : "Not listening")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(recent) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(segment.speakerLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(segment.source == .microphone ? .blue : .secondary)
                            .frame(width: 30, alignment: .leading)
                        Text(segment.text)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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

        WrapLayout(spacing: 6) {
            ForEach(QuickAction.allCases) { action in
                HUDActionButton(title: action.title, systemImage: action.systemImage) {
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
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }

        if let message = ask.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 6) {
            TextField("Ask Wikily…", text: askDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
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
                HUDIconButton("arrow.up.circle.fill", help: "Ask") { session.submitAsk() }
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
                isAskFocused ? Color.accentColor.opacity(0.6) : .primary.opacity(0.12)
            )
        )
    }

    private func askBubble(_ message: AskSession.Message) -> some View {
        HStack(alignment: .top, spacing: 5) {
            if message.role == .user {
                Spacer(minLength: 24)
                Text(message.text)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                    )
                    .foregroundStyle(.white)
            } else {
                WikilyMark(size: 13)
                Text(message.text)
                    .font(.system(size: 11))
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
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor, in: Circle())
    }
}

private struct ConfidenceBadge: View {
    var score: Double

    var body: some View {
        Text("\(Int((score * 100).rounded()))%")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.1), in: Capsule())
            .help("Match confidence")
    }
}

/// The listening indicator. Pulses continuously so a silent stretch of call
/// still reads as "running", and brightens while the VAD hears speech.
private struct PulsingDot: View {
    var isActive: Bool
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(.green, lineWidth: 1)
                    .scaleEffect(isPulsing ? 2.2 : 1)
                    .opacity(isPulsing ? 0 : 0.7)
            }
            .opacity(isActive ? 1 : 0.65)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct HUDIconButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ symbol: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.role = role
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var tint: Color {
        guard isHovering else { return .secondary }
        return role == .destructive ? .red : .primary
    }
}

private struct HUDActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
