import Foundation
import Testing
@testable import Wikily

/// Guards against the test suite writing to the real user's preferences.
///
/// This is not hypothetical. `CallSession.loadWiki` used to persist the chosen
/// folder to `UserDefaults.standard` itself, and because the unit-test target's
/// `TEST_HOST` is Wikily.app, every test run wrote into the actual
/// `com.wikily.Wikily` domain — repointing a real person's wiki folder at
/// whatever path a test happened to use. Persistence belongs to `AppSettings`,
/// which is injectable; state objects must not reach for the standard domain.
@MainActor
struct DefaultsIsolationTests {

    /// Keys any part of the app might plausibly write.
    private static let watchedKeys = [
        "wiki.folderPath",
        AppSettings.Key.wikiFolderPath,
        AppSettings.Key.qaModel,
        AppSettings.Key.suggestionFrequency,
        AppSettings.Key.confidenceThreshold,
        AppSettings.Key.hasCompletedOnboarding,
    ]

    private func snapshot() -> [String: String] {
        var values: [String: String] = [:]
        for key in Self.watchedKeys {
            if let object = UserDefaults.standard.object(forKey: key) {
                values[key] = String(describing: object)
            }
        }
        return values
    }

    @Test func loadingAWikiDoesNotTouchTheStandardDefaults() async throws {
        let before = snapshot()

        let vault = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path

        let session = CallSession()
        await session.loadWiki(directory: vault)

        // The index must actually have been built, or this asserts nothing.
        #expect(session.index.documents.count > 0)
        #expect(session.wikiFolderPath == vault)

        #expect(
            snapshot() == before,
            "CallSession wrote to UserDefaults.standard — that is the user's real preferences"
        )
    }

    @Test func appSettingsUsesAnInjectableDefaultsDomain() throws {
        // The escape hatch that makes isolation possible in the first place.
        let name = "wikily.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let before = snapshot()
        let settings = AppSettings(defaults: defaults)
        settings.wikiFolderPath = "/tmp/some-vault"

        #expect(defaults.string(forKey: AppSettings.Key.wikiFolderPath) == "/tmp/some-vault")
        #expect(snapshot() == before, "writing to an injected suite leaked into the standard domain")
    }
}
