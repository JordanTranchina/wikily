import AppKit
import Sparkle
import SwiftUI

/// One pane of the settings window.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case knowledgeBase
    case model
    case behavior
    case audio
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .knowledgeBase: "Knowledge Base"
        case .model: "Model"
        case .behavior: "Behavior"
        case .audio: "Audio"
        case .calendar: "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .knowledgeBase: "books.vertical"
        case .model: "cpu"
        case .behavior: "slider.horizontal.3"
        case .audio: "waveform"
        case .calendar: "calendar"
        }
    }

    var itemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("settings.\(rawValue)")
    }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        guard let tab = SettingsTab.allCases.first(where: { $0.itemIdentifier == itemIdentifier })
        else { return nil }
        self = tab
    }
}

/// The contents of one settings pane.
///
/// This used to be a SwiftUI `TabView`, which is where the "floating grey band"
/// in the title bar came from: in a plain `NSWindow` a `TabView` draws its own
/// segmented picker on its own backdrop, sized to the tab titles rather than to
/// the window, so it reads as a stray control laid over the chrome instead of as
/// part of it. Real Mac settings windows use a toolbar in `.preference` style,
/// which is what `SettingsWindowController` now supplies — so this view renders
/// a single pane and the window owns the switching.
///
/// The value of being conventional is that the user already knows where
/// everything is: ⌘, opens it, tabs across the top, changes take effect
/// immediately with no Save button.
@MainActor
struct SettingsRootView: View {

    @Bindable private var settings: AppSettings
    private let tab: SettingsTab
    private let updater: SPUUpdater?

    init(settings: AppSettings = .shared, tab: SettingsTab = .general, updater: SPUUpdater? = nil) {
        _settings = Bindable(settings)
        self.tab = tab
        self.updater = updater
    }

    var body: some View {
        Group {
            switch tab {
            case .general:
                GeneralSettingsView(settings: settings, updater: updater)
            case .knowledgeBase:
                KnowledgeBaseSettingsView(settings: settings)
            case .model:
                ModelSettingsView(settings: settings)
            case .behavior:
                BehaviorSettingsView(settings: settings)
            case .audio:
                AudioSettingsView(settings: settings)
            case .calendar:
                CalendarSettingsView(settings: settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Window geometry, owned by `SettingsWindowController` rather than by the views
/// — see the note there on why SwiftUI is not allowed to size this window.
enum SettingsMetrics {
    static let width: CGFloat = 540
    static let height: CGFloat = 460
    static let minimumHeight: CGFloat = 320
}

/// Shared chrome for one settings pane.
///
/// Exists so every tab gets the same width, padding and form style from one
/// place — five `Form`s configured independently drift within a release.
@MainActor
struct SettingsPane<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Secondary explanatory text under a control.
struct SettingsFootnote: View {

    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A coloured dot plus a label, used for every status row in Settings.
struct StatusIndicator: View {

    enum Level {
        case ok, warning, problem, unknown

        var color: Color {
            switch self {
            case .ok: .green
            case .warning: .orange
            case .problem: .red
            case .unknown: .secondary
            }
        }
    }

    let level: Level
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)
        }
        .labelStyle(.titleAndIcon)
    }
}

#Preview {
    SettingsRootView(
        settings: AppSettings(
            defaults: UserDefaults(suiteName: "com.wikily.Wikily.preview")!,
            launchAtLogin: .inert
        )
    )
}
