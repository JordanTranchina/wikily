import Foundation

/// Text shown in Settings that is derived rather than typed.
///
/// Pulled out of the views because these are the only parts of the settings UI
/// worth testing: a SwiftUI `Form` either lays out or it doesn't, but "3 seconds
/// ago" versus "in 3 seconds", and the sentence a half-downloaded speech model
/// produces, are logic that can quietly be wrong.
enum SettingsFormatting {

    /// "1 page" / "12 pages" — English pluralisation only, matching the rest of
    /// the app's copy. Worth stating: this is not localised, and if Wikily ever
    /// is, every one of these becomes a stringsdict entry.
    static func count(_ value: Int, singular: String, plural: String? = nil) -> String {
        let plural = plural ?? singular + "s"
        return "\(value.formatted()) \(value == 1 ? singular : plural)"
    }

    /// When the index was last built, relative to now.
    ///
    /// Clamped to the past. A vault indexed on a machine whose clock then moved
    /// backwards would otherwise read "in 4 hours", which reads as a bug in a
    /// panel whose whole job is telling the user their data is current.
    static func lastIndexed(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never indexed" }

        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Indexed just now" }

        var style = Date.RelativeFormatStyle()
        style.presentation = .named
        return "Indexed \(min(date, now).formatted(style))"
    }

    /// One line describing the on-device speech model's state.
    ///
    /// Every branch says what it means for the user rather than naming the
    /// state, because "notInstalled" is not a thing anyone can act on and
    /// "transcription won't work yet" is.
    static func speechModel(_ state: SpeechModelInstaller.State, locale: Locale?) -> String {
        let language = locale.map(languageName) ?? "your language"
        switch state {
        case .unsupported:
            return "On-device transcription isn't available for \(language) on this Mac."
        case .notInstalled:
            return "Not installed — Wikily can't transcribe calls until it is."
        case .downloading(let fraction):
            guard fraction > 0 else { return "Downloading…" }
            return "Downloading… \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .installed:
            return "Installed for \(language). Transcription runs entirely on this Mac."
        case .failed(let message):
            return "Download failed: \(message)"
        }
    }

    static func languageName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    /// Status line for a model backend in the picker.
    ///
    /// Unavailable backends stay on screen with their reason attached — hiding
    /// them turns "Apple Intelligence is switched off" into "Apple Intelligence
    /// doesn't exist", and the user has no way back from the second one.
    static func availability(_ availability: ModelAvailability) -> String {
        availability.message ?? "Ready"
    }
}
