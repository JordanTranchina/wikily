import Foundation
import OSLog
import Speech

/// Manages the on-device speech model for a locale.
///
/// `SpeechTranscriber` runs entirely on-device, but the model for a given
/// language has to be installed first — this is the one moment in Wikily's
/// lifetime that needs the network. After it completes, transcription works with
/// networking fully disabled, which is the whole point.
///
/// This replaces `scripts/setup-whisper.sh`, the `tauri.whisper.conf.json`
/// sidecar overlay, and the `LOCAL_TRANSCRIPTION_UNAVAILABLE` degradation path
/// in `src-tauri/src/transcribe.rs` — the feature that was scaffolded but never
/// shipped in the Tauri build.
enum SpeechModelInstaller {

    private static let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "SpeechModelInstaller"
    )

    enum State: Sendable, Equatable {
        /// The locale has no on-device model and never will.
        case unsupported
        /// Supported but not installed — needs a download.
        case notInstalled
        case downloading(fraction: Double)
        case installed
        case failed(message: String)

        var isReady: Bool { self == .installed }
    }

    enum InstallerError: LocalizedError {
        case localeUnsupported(String)

        var errorDescription: String? {
            switch self {
            case .localeUnsupported(let identifier):
                "On-device transcription isn't available for \(identifier)."
            }
        }
    }

    /// Whether the framework supports on-device transcription on this machine at
    /// all, independent of any particular locale.
    static var isSupported: Bool {
        SpeechTranscriber.isAvailable
    }

    /// The best supported locale for the user's current language, if any.
    ///
    /// `Locale.current` is rarely an exact match for a supported locale
    /// (`en_US_POSIX`, region variants), so this asks the framework to map it.
    static func resolvedLocale(preferring locale: Locale = .current) async -> Locale? {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return match
        }
        // Fall back to any installed locale before giving up — a user with only
        // en_GB installed should still get transcription.
        if let installed = await SpeechTranscriber.installedLocales.first {
            return installed
        }
        return await SpeechTranscriber.supportedLocales.first
    }

    static func state(for locale: Locale) async -> State {
        guard isSupported else { return .unsupported }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        switch await AssetInventory.status(forModules: [module]) {
        case .unsupported: return .unsupported
        case .supported: return .notInstalled
        case .downloading: return .downloading(fraction: 0)
        case .installed: return .installed
        @unknown default: return .notInstalled
        }
    }

    /// Download and install the model for `locale`, reporting progress.
    ///
    /// Safe to call when the model is already installed: the framework returns
    /// no installation request and this reports `.installed` immediately.
    static func install(
        locale: Locale,
        onProgress: @escaping @Sendable (State) -> Void
    ) async {
        guard isSupported else {
            onProgress(.unsupported)
            return
        }

        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            // Reserving the locale keeps the system from evicting the model to
            // reclaim disk while Wikily still depends on it.
            try await AssetInventory.reserve(locale: locale)

            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [module]
            ) else {
                onProgress(.installed)
                return
            }

            onProgress(.downloading(fraction: 0))

            let observation = Task { @Sendable in
                // Progress is KVO-based; poll it rather than bridging KVO into
                // async, which would need a retained observer for a value read
                // once a second.
                while !Task.isCancelled {
                    let fraction = request.progress.fractionCompleted
                    if fraction > 0, fraction < 1 {
                        onProgress(.downloading(fraction: fraction))
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { observation.cancel() }

            try await request.downloadAndInstall()
            onProgress(.installed)
            logger.info("Speech model installed for \(locale.identifier, privacy: .public)")
        } catch {
            logger.error("Speech model install failed: \(error.localizedDescription, privacy: .public)")
            onProgress(.failed(message: error.localizedDescription))
        }
    }

    /// Release the locale reservation, letting the system reclaim the model.
    static func release(locale: Locale) async {
        await AssetInventory.release(reservedLocale: locale)
    }
}
