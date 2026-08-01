import SwiftUI

/// Wikily — a local-first call companion.
///
/// `LSUIElement` is set in the build settings, so there is no Dock icon and no
/// main window: the app lives as a floating overlay panel plus a menu-bar item.
/// Both arrive in later phases; for now this is the minimal shell that proves
/// the project builds and launches.
@main
struct WikilyApp: App {
    var body: some Scene {
        // A `Settings` scene is the only scene an accessory app needs to declare.
        // The real settings UI lands in Phase 6.
        Settings {
            Text("Wikily")
                .padding()
        }
    }
}
