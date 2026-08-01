import Foundation
import OSLog

/// Every user-adjustable preference in Wikily, in one place.
///
/// Before this existed, persistence was wherever the feature that needed it
/// happened to be: `CallSession` wrote a wiki folder straight to
/// `UserDefaults`, `ModelDescriptor` was `Codable` but nothing ever saved one,
/// and the audio device ids in `CallCaptureSession.Configuration` had no source
/// at all. Three different answers to "where does this live" is two too many,
/// and the settings UI needs a single object to bind to regardless.
///
/// **Why keys are namespaced.** `UserDefaults` for a non-sandboxed app is a
/// flat, shared, permanent namespace — a key called `"threshold"` is a landmine
/// for whoever adds the next feature. Everything here is `settings.<area>.<name>`
/// so the domain stays legible in `defaults read com.wikily.Wikily`, which is
/// how this gets debugged in practice.
///
/// **Why `didSet` rather than an explicit save call.** SwiftUI binds directly to
/// these properties (`@Bindable`), so a `Toggle` writes the property and nothing
/// else. Any design where persistence is a separate step is a design where some
/// control eventually forgets to take it.
@MainActor
@Observable
final class AppSettings {

    /// The instance the app and the settings scene share.
    ///
    /// A singleton because the `Settings` scene is declared in `WikilyApp` and
    /// the rest of the app is built in `applicationDidFinishLaunching` — there is
    /// no common owner to inject from, and inventing one to thread a preferences
    /// object through would be more machinery than the problem deserves. Tests
    /// use `init(defaults:)` with their own suite and never touch this.
    static let shared = AppSettings()

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "AppSettings")

    @ObservationIgnored private let defaults: UserDefaults

    /// Suppresses write-back while `init` is populating properties from disk.
    /// Without it, every launch would rewrite every key with the value it just
    /// read, which makes "the user has never set this" indistinguishable from
    /// "the user chose the default".
    @ObservationIgnored private var isRestoring = true

    // MARK: - Keys

    enum Key {
        static let launchAtLogin = "settings.general.launchAtLogin"
        static let wikiFolderPath = "settings.wiki.folderPath"
        static let wikiIndexStats = "settings.wiki.indexStats"
        static let qaModel = "settings.model.qa"
        static let suggestionFrequency = "settings.behavior.suggestionFrequency"
        static let confidenceThreshold = "settings.behavior.confidenceThreshold"
        static let inputDeviceID = "settings.audio.inputDeviceID"
        static let outputDeviceID = "settings.audio.outputDeviceID"
        static let capturesMicrophone = "settings.audio.capturesMicrophone"
        static let hasCompletedOnboarding = "settings.onboarding.completed"

        /// Phase 4's key, written by `CallSession` before this type existed.
        /// Read once at startup and carried into `wikiFolderPath`.
        static let legacyWikiFolderPath = "wiki.folderPath"
    }

    // MARK: - General

    /// The user's *intent* to launch at login. The registration itself lives in
    /// `LaunchAtLogin`, and the system is allowed to disagree — a user can revoke
    /// the login item in System Settings without Wikily being told. `reconcile()`
    /// resolves that on the next launch.
    var launchAtLogin: Bool = false {
        didSet {
            guard !isRestoring, launchAtLogin != oldValue else { return }
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            do {
                try launchAtLoginControl.setEnabled(launchAtLogin)
                launchAtLoginError = nil
            } catch {
                // Left visible rather than silently reverted: a toggle that snaps
                // back with no explanation is the worst of both outcomes.
                launchAtLoginError = error.localizedDescription
                logger.error("""
                    Login item update failed: \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
    }

    /// Last failure from registering the login item, for the General tab to show.
    private(set) var launchAtLoginError: String?

    // MARK: - Knowledge base

    /// Absolute path of the folder holding the user's markdown wiki.
    var wikiFolderPath: String? {
        didSet {
            guard !isRestoring, wikiFolderPath != oldValue else { return }
            defaults.set(wikiFolderPath, forKey: Key.wikiFolderPath)
        }
    }

    /// What the last successful index produced. Persisted so the Knowledge Base
    /// tab can show real numbers the moment it opens, instead of either lying
    /// ("0 pages") or re-scanning the vault every time the window appears.
    var indexStats: IndexStats? {
        didSet {
            guard !isRestoring, indexStats != oldValue else { return }
            write(indexStats, forKey: Key.wikiIndexStats)
        }
    }

    struct IndexStats: Sendable, Equatable, Codable {
        var documentCount: Int
        var tokenCount: Int
        var indexedAt: Date
    }

    // MARK: - Model

    /// The Q&A backend the user picked, or `nil` to let Wikily choose.
    ///
    /// Stored as the whole descriptor rather than an id, because resolving an id
    /// back to a model requires the user's local server to be running — and the
    /// one moment this is read is app launch, when it may well not be.
    var qaModel: ModelDescriptor? {
        didSet {
            guard !isRestoring, qaModel != oldValue else { return }
            write(qaModel, forKey: Key.qaModel)
        }
    }

    // MARK: - Behavior

    var suggestionFrequency: WikiSuggestionFrequency = .medium {
        didSet {
            guard !isRestoring, suggestionFrequency != oldValue else { return }
            defaults.set(suggestionFrequency.rawValue, forKey: Key.suggestionFrequency)
        }
    }

    /// Raw `0...1` match confidence gate. Stored as the number rather than as a
    /// `WikiConfidencePreset` case so that retuning what "Medium" means in a
    /// future release doesn't silently change every existing user's behaviour.
    var confidenceThreshold: Double = WikiMatchCoordinator.defaultThreshold {
        didSet {
            guard !isRestoring, confidenceThreshold != oldValue else { return }
            defaults.set(confidenceThreshold, forKey: Key.confidenceThreshold)
        }
    }

    /// The preset nearest the stored threshold, for the segmented picker.
    var confidencePreset: WikiConfidencePreset {
        get { WikiConfidencePreset.closest(to: confidenceThreshold) }
        set { confidenceThreshold = newValue.threshold }
    }

    // MARK: - Audio

    /// CoreAudio device UIDs, or `AudioDevice.systemDefaultID` for "follow the
    /// system". UIDs rather than `AudioObjectID`s because the latter are assigned
    /// per boot and would point at an unrelated device after a restart.
    var inputDeviceID: String = AudioDevice.systemDefaultID {
        didSet {
            guard !isRestoring, inputDeviceID != oldValue else { return }
            defaults.set(inputDeviceID, forKey: Key.inputDeviceID)
        }
    }

    var outputDeviceID: String = AudioDevice.systemDefaultID {
        didSet {
            guard !isRestoring, outputDeviceID != oldValue else { return }
            defaults.set(outputDeviceID, forKey: Key.outputDeviceID)
        }
    }

    /// Whether to capture the user's own voice alongside the far end.
    ///
    /// Defaults on: a suggestion triggered by what *you* just said is half the
    /// product, and a user who only wants the other side can turn it off.
    var capturesMicrophone: Bool = true {
        didSet {
            guard !isRestoring, capturesMicrophone != oldValue else { return }
            defaults.set(capturesMicrophone, forKey: Key.capturesMicrophone)
        }
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool = false {
        didSet {
            guard !isRestoring, hasCompletedOnboarding != oldValue else { return }
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        }
    }

    // MARK: - Wiring

    /// Re-index the current folder, returning what the new index contains.
    ///
    /// Installed by whoever owns the `CallSession`, since this object
    /// deliberately knows nothing about one. It returns stats rather than
    /// updating them itself so the contract is visible in the type: whoever
    /// rebuilds the index is the only one who can say what is in it.
    ///
    /// `nil` until installed, and `rescanWiki()` falls back to scanning directly
    /// — Settings has to show honest numbers even with no call session around.
    @ObservationIgnored
    var wikiReloadHandler: (@MainActor (String) async -> WikiIndex.Stats?)?

    // MARK: - Init

    @ObservationIgnored private let launchAtLoginControl: LaunchAtLoginControl

    /// - Parameter launchAtLogin: injected so tests never hand the running
    ///   binary to `SMAppService`. Pass `.inert` anywhere the real registration
    ///   would be wrong.
    init(
        defaults: UserDefaults = .standard,
        launchAtLogin launchAtLoginControl: LaunchAtLoginControl = .system
    ) {
        self.defaults = defaults
        self.launchAtLoginControl = launchAtLoginControl

        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        wikiFolderPath = Self.restoreWikiFolderPath(from: defaults)
        indexStats = Self.read(IndexStats.self, forKey: Key.wikiIndexStats, from: defaults)
        qaModel = Self.read(ModelDescriptor.self, forKey: Key.qaModel, from: defaults)

        if let raw = defaults.string(forKey: Key.suggestionFrequency),
           let frequency = WikiSuggestionFrequency(rawValue: raw) {
            suggestionFrequency = frequency
        }
        if defaults.object(forKey: Key.confidenceThreshold) != nil {
            // Clamped because the stored value survives a downgrade, a manual
            // `defaults write`, and any future change to what the presets mean.
            // An out-of-range threshold silently matches everything or nothing.
            confidenceThreshold = min(max(defaults.double(forKey: Key.confidenceThreshold), 0), 1)
        }

        inputDeviceID = defaults.string(forKey: Key.inputDeviceID) ?? AudioDevice.systemDefaultID
        outputDeviceID = defaults.string(forKey: Key.outputDeviceID) ?? AudioDevice.systemDefaultID
        if defaults.object(forKey: Key.capturesMicrophone) != nil {
            capturesMicrophone = defaults.bool(forKey: Key.capturesMicrophone)
        }
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)

        isRestoring = false
    }

    /// Read the wiki folder, taking Phase 4's un-namespaced key into account.
    ///
    /// The legacy key is copied forward rather than read-and-forgotten, because
    /// the alternative is a user who already chose a folder being shown an empty
    /// Knowledge Base tab and concluding the feature is broken.
    private static func restoreWikiFolderPath(from defaults: UserDefaults) -> String? {
        if let current = defaults.string(forKey: Key.wikiFolderPath) {
            return current
        }
        guard let legacy = defaults.string(forKey: Key.legacyWikiFolderPath) else { return nil }
        defaults.set(legacy, forKey: Key.wikiFolderPath)
        return legacy
    }

    // MARK: - Derived configuration

    /// The audio configuration a call should start with.
    ///
    /// Lives here so `CallSession` never has to know which preference maps to
    /// which capture field — it asks for a configuration and gets one.
    var captureConfiguration: CallCaptureSession.Configuration {
        CallCaptureSession.Configuration(
            outputDeviceID: outputDeviceID == AudioDevice.systemDefaultID ? nil : outputDeviceID,
            inputDeviceID: inputDeviceID == AudioDevice.systemDefaultID ? nil : inputDeviceID,
            capturesMicrophone: capturesMicrophone
        )
    }

    /// A matcher seeded with the user's sensitivity settings.
    var matchCoordinator: WikiMatchCoordinator {
        WikiMatchCoordinator(
            threshold: confidenceThreshold,
            suggestionFrequency: suggestionFrequency
        )
    }

    /// Point Wikily at a new folder and index it.
    func setWikiFolder(_ path: String) async throws {
        wikiFolderPath = path
        try await rescanWiki()
    }

    /// Re-index the chosen folder and record what it produced.
    ///
    /// Throws only from the direct-scan fallback — a missing or unreadable
    /// folder. The handler path swallows its own errors into `CallSession`'s
    /// error message, which is where the rest of the app already looks.
    func rescanWiki() async throws {
        guard let path = wikiFolderPath else { return }

        if let wikiReloadHandler {
            if let stats = await wikiReloadHandler(path) {
                indexStats = IndexStats(
                    documentCount: stats.documentCount,
                    tokenCount: stats.tokenCount,
                    indexedAt: Date()
                )
            }
            return
        }

        // Detached because a large vault takes long enough to drop frames, and
        // this runs while a settings window is on screen.
        let index = try await Task.detached(priority: .userInitiated) {
            try WikiIndexCache.buildIndex(directory: path)
        }.value
        indexStats = IndexStats(
            documentCount: index.stats.documentCount,
            tokenCount: index.stats.tokenCount,
            indexedAt: Date()
        )
    }

    /// Bring the recorded launch-at-login intent back in line with what the
    /// system actually has registered. Called once at launch.
    func reconcileLaunchAtLogin() {
        let actual = launchAtLoginControl.isEnabled()
        guard actual != launchAtLogin else { return }
        logger.info("""
            Login item disagrees with stored intent \
            (system=\(actual, privacy: .public)); trusting the system.
            """)
        isRestoring = true
        launchAtLogin = actual
        isRestoring = false
        defaults.set(actual, forKey: Key.launchAtLogin)
    }

    /// Wipe every key this type owns. Only used by tests and by a future
    /// "reset settings" affordance; the legacy key goes too so a reset is a
    /// genuine reset rather than one that resurrects the old folder.
    func resetAll() {
        for key in [
            Key.launchAtLogin, Key.wikiFolderPath, Key.wikiIndexStats, Key.qaModel,
            Key.suggestionFrequency, Key.confidenceThreshold, Key.inputDeviceID,
            Key.outputDeviceID, Key.capturesMicrophone, Key.hasCompletedOnboarding,
            Key.legacyWikiFolderPath,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Codable storage

    private func write<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("""
                Could not persist \(key, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    /// Returns `nil` for anything that no longer decodes — a descriptor written
    /// by an older build, say. Dropping the value is right: the defaults below
    /// are all usable, whereas refusing to launch over a stale preference is not.
    private static func read<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        from defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
