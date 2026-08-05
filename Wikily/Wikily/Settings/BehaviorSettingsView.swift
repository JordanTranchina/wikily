import SwiftUI

/// Settings › Behavior: how eagerly Wikily interrupts.
///
/// Two knobs that are easy to confuse, so the copy separates them explicitly.
/// Frequency controls *how often* the overlay may speak up; confidence controls
/// *how sure* it has to be before it does. A user who finds Wikily noisy will
/// reach for whichever they see first, and getting the wrong one makes the
/// problem worse rather than doing nothing.
@MainActor
struct BehaviorSettingsView: View {

    @Bindable var settings: AppSettings

    var body: some View {
        SettingsPane {
            Section {
                Picker("Suggestions", selection: $settings.suggestionFrequency) {
                    ForEach(WikiSuggestionFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Frequency")
            } footer: {
                SettingsFootnote(frequencyExplanation)
            }

            Section {
                Picker("Confidence", selection: $settings.confidencePreset) {
                    ForEach(WikiConfidencePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(
                    "Threshold",
                    value: settings.confidenceThreshold
                        .formatted(.number.precision(.fractionLength(2)))
                )
            } header: {
                Text("Confidence")
            } footer: {
                SettingsFootnote(
                    "How strong a match has to be before a card appears. Higher means "
                        + "fewer, surer suggestions; lower surfaces more pages and more "
                        + "wrong ones. Changes apply to the next call."
                )
            }

            Section {
                Slider(value: $settings.overlayOpacity, in: 0...1) {
                    Text("Overlay background")
                } minimumValueLabel: {
                    Text("Transparent").font(.caption)
                } maximumValueLabel: {
                    Text("Solid").font(.caption)
                }

                Picker("Overlay text size", selection: $settings.overlayFontSize) {
                    ForEach(Self.fontSizeOptions, id: \.self) { size in
                        Text("\(size) pt").tag(size)
                    }
                }
            } header: {
                Text("Overlay")
            } footer: {
                SettingsFootnote(
                    "How solid the HUD's background looks over your call, and how "
                        + "large its text reads. More transparent keeps the call "
                        + "behind it visible; more solid is easier to read against a "
                        + "bright window. Both take effect immediately."
                )
            }
        }
    }

    /// The point sizes offered for the HUD's base text. Matches the reference
    /// (`OverlayTheme.referenceFontSize`, `12`) and the default
    /// (`AppSettings.overlayFontSize`, `14`) so both land on an actual option
    /// rather than between two of them.
    private static let fontSizeOptions = Array(11...18)

    private var frequencyExplanation: String {
        let window = settings.suggestionFrequency.windowSize
        return "Wikily matches against the last "
            + SettingsFormatting.count(window, singular: "thing", plural: "things")
            + " said. A shorter window reacts faster to a change of subject; a "
            + "longer one waits to be sure the subject really changed."
    }
}
