import Foundation
import SwiftUI

/// Observable wrapper around `SpeechModelInstaller`.
///
/// Two screens need the same thing — the model's state, a download button, and
/// live progress — and they are the first-run wizard and the Model tab. Keeping
/// one object means the wizard cannot drift into telling the user something
/// different from what Settings says about the same model.
@MainActor
@Observable
final class SpeechModelState {

    private(set) var locale: Locale?
    private(set) var state: SpeechModelInstaller.State = .notInstalled
    private(set) var isInstalling = false

    var isReady: Bool { state.isReady }

    func refresh() async {
        let locale = await SpeechModelInstaller.resolvedLocale()
        self.locale = locale
        guard let locale else {
            state = .unsupported
            return
        }
        state = await SpeechModelInstaller.state(for: locale)
    }

    func install() {
        guard let locale, !isInstalling else { return }
        isInstalling = true

        Task {
            await SpeechModelInstaller.install(locale: locale) { state in
                // Progress arrives from the installer's own polling task, so
                // every update has to be hopped back to the main actor.
                Task { @MainActor in self.state = state }
            }
            isInstalling = false
            await refresh()
        }
    }

    // MARK: - Presentation

    var description: String {
        SettingsFormatting.speechModel(state, locale: locale)
    }

    var level: StatusIndicator.Level {
        switch state {
        case .installed: .ok
        case .downloading: .warning
        case .notInstalled, .failed, .unsupported: .problem
        }
    }

    var canInstall: Bool {
        switch state {
        case .notInstalled, .failed: true
        case .installed, .downloading, .unsupported: false
        }
    }

    var installTitle: String {
        if case .failed = state { return "Try Again" }
        return "Download Speech Model"
    }

    /// Download progress in `0...1`, or `nil` when nothing is downloading.
    var progress: Double? {
        guard case .downloading(let fraction) = state, fraction > 0 else { return nil }
        return fraction
    }
}
