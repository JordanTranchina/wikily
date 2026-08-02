import Foundation
import Testing
@testable import Wikily

/// Covers the persistence layer under Settings: what survives a relaunch, what
/// the Phase 4 migration does, and what a hostile `defaults` domain can't break.
///
/// Every test gets its own `UserDefaults` suite. Sharing the standard domain
/// would make these order-dependent against each other *and* destructive to
/// whatever the developer running them has configured in the real app.
@MainActor
struct AppSettingsTests {

    /// A settings store over a throwaway domain, torn down afterwards.
    ///
    /// `launchAtLogin: .inert` is not optional: the real control hands the test
    /// runner to `SMAppService`, which would add `xctest` to the user's Login
    /// Items.
    private func withSettings(
        seed: [String: Any] = [:],
        _ body: (AppSettings, UserDefaults) throws -> Void
    ) throws {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        for (key, value) in seed {
            defaults.set(value, forKey: key)
        }
        try body(AppSettings(defaults: defaults, launchAtLogin: .inert), defaults)
    }

    // MARK: - Defaults

    @Test func anEmptyDomainProducesUsableDefaults() throws {
        try withSettings { settings, _ in
            #expect(settings.wikiFolderPath == nil)
            #expect(settings.qaModel == nil)
            #expect(settings.indexStats == nil)
            #expect(settings.suggestionFrequency == .medium)
            #expect(settings.confidenceThreshold == WikiMatchCoordinator.defaultThreshold)
            #expect(settings.overlayOpacity == 0.6)
            #expect(settings.overlayFontSize == 14)
            #expect(settings.inputDeviceID == AudioDevice.systemDefaultID)
            #expect(settings.outputDeviceID == AudioDevice.systemDefaultID)
            #expect(settings.capturesMicrophone)
            #expect(!settings.launchAtLogin)
            #expect(!settings.hasCompletedOnboarding)
        }
    }

    /// Restoring must not write. If it did, "never set" and "set to the default"
    /// would be indistinguishable, and a later change to a default would not
    /// reach any existing install.
    @Test func restoringDoesNotMaterialiseDefaultsIntoTheDomain() throws {
        try withSettings { _, defaults in
            #expect(defaults.object(forKey: AppSettings.Key.capturesMicrophone) == nil)
            #expect(defaults.object(forKey: AppSettings.Key.confidenceThreshold) == nil)
            #expect(defaults.object(forKey: AppSettings.Key.suggestionFrequency) == nil)
            #expect(defaults.object(forKey: AppSettings.Key.overlayOpacity) == nil)
            #expect(defaults.object(forKey: AppSettings.Key.overlayFontSize) == nil)
        }
    }

    // MARK: - Round trips

    @Test func everySettingSurvivesARelaunch() throws {
        let model = ModelDescriptor.localServer(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            modelID: "gemma3:4b",
            serverName: "Ollama"
        )
        let stats = AppSettings.IndexStats(
            documentCount: 42,
            tokenCount: 1337,
            indexedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try withSettings { settings, defaults in
            settings.wikiFolderPath = "/tmp/vault"
            settings.qaModel = model
            settings.indexStats = stats
            settings.suggestionFrequency = .high
            settings.confidenceThreshold = 0.55
            settings.overlayOpacity = 0.25
            settings.overlayFontSize = 16
            settings.inputDeviceID = "MicUID"
            settings.outputDeviceID = "SpeakerUID"
            settings.capturesMicrophone = false
            settings.hasCompletedOnboarding = true

            let reloaded = AppSettings(defaults: defaults, launchAtLogin: .inert)
            #expect(reloaded.wikiFolderPath == "/tmp/vault")
            #expect(reloaded.qaModel == model)
            #expect(reloaded.indexStats == stats)
            #expect(reloaded.suggestionFrequency == .high)
            #expect(reloaded.confidenceThreshold == 0.55)
            #expect(reloaded.overlayOpacity == 0.25)
            #expect(reloaded.overlayFontSize == 16)
            #expect(reloaded.inputDeviceID == "MicUID")
            #expect(reloaded.outputDeviceID == "SpeakerUID")
            #expect(!reloaded.capturesMicrophone)
            #expect(reloaded.hasCompletedOnboarding)
        }
    }

    /// The descriptor is stored whole rather than by id, precisely so a model on
    /// a server that is not running still restores.
    @Test func aLocalServerModelRestoresWithoutTheServerRunning() throws {
        try withSettings { settings, defaults in
            settings.qaModel = ModelDescriptor.localServer(
                baseURL: URL(string: "http://127.0.0.1:1234")!,
                modelID: "qwen2.5-7b-instruct",
                serverName: "LM Studio"
            )

            let restored = try #require(
                AppSettings(defaults: defaults, launchAtLogin: .inert).qaModel
            )
            #expect(restored.backend == .localServer)
            #expect(restored.modelID == "qwen2.5-7b-instruct")
            #expect(restored.serverBaseURL?.port == 1234)
            #expect(restored.makeService() != nil)
        }
    }

    @Test func clearingAnOptionalRemovesItRatherThanStoringNull() throws {
        try withSettings { settings, defaults in
            settings.qaModel = .appleFoundation
            settings.qaModel = nil

            #expect(defaults.object(forKey: AppSettings.Key.qaModel) == nil)
            #expect(AppSettings(defaults: defaults, launchAtLogin: .inert).qaModel == nil)
        }
    }

    // MARK: - Migration

    @Test func thePhase4WikiFolderKeyIsCarriedForward() throws {
        try withSettings(
            seed: [AppSettings.Key.legacyWikiFolderPath: "/Users/someone/wiki"]
        ) { settings, defaults in
            #expect(settings.wikiFolderPath == "/Users/someone/wiki")
            // Written through, so the migration happens once rather than on
            // every launch.
            #expect(
                defaults.string(forKey: AppSettings.Key.wikiFolderPath)
                    == "/Users/someone/wiki"
            )
        }
    }

    /// A namespaced value already exists, so the legacy key is stale and must
    /// not win — otherwise choosing a new folder in Settings would be undone by
    /// the next launch.
    @Test func theNamespacedWikiFolderBeatsTheLegacyKey() throws {
        try withSettings(seed: [
            AppSettings.Key.legacyWikiFolderPath: "/old/vault",
            AppSettings.Key.wikiFolderPath: "/new/vault",
        ]) { settings, _ in
            #expect(settings.wikiFolderPath == "/new/vault")
        }
    }

    /// `CallSession.restorePersistedWiki()` still reads the un-namespaced key.
    /// Until that call site moves, a folder chosen in Settings has to land there
    /// too or it is forgotten on relaunch.
    /// The mirror-on-write is gone: `CallSession` reads `AppSettings` now, so
    /// there is nothing left to mirror *to*. Reading the legacy key **forward**
    /// still matters — anyone who chose a folder before this change would
    /// otherwise open an empty Knowledge Base tab and conclude it broke.
    @Test func aLegacyWikiFolderIsMigratedForwardOnce() throws {
        try withSettings(seed: [AppSettings.Key.legacyWikiFolderPath: "/tmp/legacy-vault"]) {
            settings, defaults in
            #expect(settings.wikiFolderPath == "/tmp/legacy-vault")
            // Copied forward, not merely read, so the migration is idempotent.
            #expect(defaults.string(forKey: AppSettings.Key.wikiFolderPath) == "/tmp/legacy-vault")
        }
    }

    @Test func theCurrentKeyWinsOverALegacyOne() throws {
        try withSettings(seed: [
            AppSettings.Key.wikiFolderPath: "/tmp/current",
            AppSettings.Key.legacyWikiFolderPath: "/tmp/legacy",
        ]) { settings, _ in
            #expect(settings.wikiFolderPath == "/tmp/current")
        }
    }

    @Test func writingTheWikiFolderNoLongerTouchesTheLegacyKey() throws {
        try withSettings { settings, defaults in
            settings.wikiFolderPath = "/tmp/vault"
            #expect(defaults.string(forKey: AppSettings.Key.legacyWikiFolderPath) == nil)
        }
    }

    // MARK: - Hostile input

    @Test func anOutOfRangeThresholdIsClamped() throws {
        try withSettings(seed: [AppSettings.Key.confidenceThreshold: 9.0]) { settings, _ in
            #expect(settings.confidenceThreshold == 1)
        }
        try withSettings(seed: [AppSettings.Key.confidenceThreshold: -3.0]) { settings, _ in
            #expect(settings.confidenceThreshold == 0)
        }
    }

    @Test func anOutOfRangeOverlayOpacityIsClamped() throws {
        try withSettings(seed: [AppSettings.Key.overlayOpacity: 4.0]) { settings, _ in
            #expect(settings.overlayOpacity == 1)
        }
        try withSettings(seed: [AppSettings.Key.overlayOpacity: -1.0]) { settings, _ in
            #expect(settings.overlayOpacity == 0)
        }
    }

    @Test func anOutOfRangeFontSizeIsClamped() throws {
        try withSettings(seed: [AppSettings.Key.overlayFontSize: 99]) { settings, _ in
            #expect(settings.overlayFontSize == 20)
        }
        try withSettings(seed: [AppSettings.Key.overlayFontSize: 1]) { settings, _ in
            #expect(settings.overlayFontSize == 10)
        }
    }

    @Test func anUnknownSuggestionFrequencyFallsBackToTheDefault() throws {
        try withSettings(
            seed: [AppSettings.Key.suggestionFrequency: "occasionally"]
        ) { settings, _ in
            #expect(settings.suggestionFrequency == .medium)
        }
    }

    @Test func anUndecodableModelIsDroppedRatherThanCrashing() throws {
        try withSettings(
            seed: [AppSettings.Key.qaModel: Data("not json".utf8)]
        ) { settings, _ in
            #expect(settings.qaModel == nil)
        }
    }

    // MARK: - Derived configuration

    /// The sentinel means "follow the system", which downstream expresses as
    /// `nil` — passing the literal string "default" through would send
    /// `AudioDeviceStore` hunting for a device with that UID.
    @Test func theSystemDefaultSentinelBecomesNilInTheCaptureConfiguration() throws {
        try withSettings { settings, _ in
            let configuration = settings.captureConfiguration
            #expect(configuration.inputDeviceID == nil)
            #expect(configuration.outputDeviceID == nil)
            #expect(configuration.capturesMicrophone)
        }
    }

    @Test func chosenDevicesReachTheCaptureConfiguration() throws {
        try withSettings { settings, _ in
            settings.inputDeviceID = "MicUID"
            settings.outputDeviceID = "SpeakerUID"
            settings.capturesMicrophone = false

            let configuration = settings.captureConfiguration
            #expect(configuration.inputDeviceID == "MicUID")
            #expect(configuration.outputDeviceID == "SpeakerUID")
            #expect(!configuration.capturesMicrophone)
        }
    }

    @Test func theMatchCoordinatorIsSeededFromBehaviorSettings() throws {
        try withSettings { settings, _ in
            settings.confidenceThreshold = 0.5
            settings.suggestionFrequency = .high

            let coordinator = settings.matchCoordinator
            #expect(coordinator.threshold == 0.5)
            #expect(coordinator.suggestionFrequency == .high)
        }
    }

    /// The stored value is the raw threshold, so the preset is a lossy view of
    /// it. Setting the preset must move the threshold onto that preset exactly.
    @Test func theConfidencePresetMapsBothWays() throws {
        try withSettings { settings, _ in
            settings.confidencePreset = .high
            #expect(settings.confidenceThreshold == WikiConfidencePreset.high.threshold)

            settings.confidenceThreshold = WikiMatchCoordinator.defaultThreshold
            #expect(settings.confidencePreset == .medium)

            // An arbitrary value snaps to the nearest preset for display without
            // being rewritten.
            settings.confidenceThreshold = 0.54
            #expect(settings.confidencePreset == .high)
            #expect(settings.confidenceThreshold == 0.54)
        }
    }

    // MARK: - Re-scan

    @Test func rescanRecordsWhatTheHandlerReports() async throws {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults, launchAtLogin: .inert)
        settings.wikiFolderPath = "/tmp/vault"
        settings.wikiReloadHandler = { _ in
            WikiIndex.Stats(documentCount: 7, tokenCount: 300)
        }

        try await settings.rescanWiki()

        let stats = try #require(settings.indexStats)
        #expect(stats.documentCount == 7)
        #expect(stats.tokenCount == 300)
    }

    @Test func rescanWithNoFolderIsAHarmlessNoOp() async throws {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults, launchAtLogin: .inert)
        try await settings.rescanWiki()
        #expect(settings.indexStats == nil)
    }

    // MARK: - Reset

    @Test func resetClearsTheLegacyKeyToo() throws {
        try withSettings(
            seed: [AppSettings.Key.legacyWikiFolderPath: "/old/vault"]
        ) { settings, defaults in
            settings.resetAll()
            #expect(defaults.string(forKey: AppSettings.Key.legacyWikiFolderPath) == nil)
            #expect(
                AppSettings(defaults: defaults, launchAtLogin: .inert).wikiFolderPath == nil
            )
        }
    }
}
