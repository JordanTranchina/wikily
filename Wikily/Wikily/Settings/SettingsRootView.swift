import SwiftUI

/// The contents of the app's `Settings` scene.
///
/// A standard macOS preferences window with toolbar tabs, not a bespoke
/// dashboard. Wikily is an `LSUIElement` app with no main window, so this is the
/// only conventional surface it has, and the value of it being conventional is
/// that the user already knows where everything is — ⌘, opens it, tabs across
/// the top, changes take effect immediately with no Save button.
///
/// Reached from the menu bar rather than a menu-bar-less app's ⌘, alone; see
/// `MenuBarController.openSettings()`.
@MainActor
struct SettingsRootView: View {

    @Bindable private var settings: AppSettings

    init(settings: AppSettings = .shared) {
        _settings = Bindable(settings)
    }

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            KnowledgeBaseSettingsView(settings: settings)
                .tabItem { Label("Knowledge Base", systemImage: "books.vertical") }

            ModelSettingsView(settings: settings)
                .tabItem { Label("Model", systemImage: "cpu") }

            BehaviorSettingsView(settings: settings)
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }

            AudioSettingsView(settings: settings)
                .tabItem { Label("Audio", systemImage: "waveform") }
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
