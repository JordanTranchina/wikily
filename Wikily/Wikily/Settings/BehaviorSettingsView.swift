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
        }
    }

    private var frequencyExplanation: String {
        let window = settings.suggestionFrequency.windowSize
        return "Wikily matches against the last "
            + SettingsFormatting.count(window, singular: "thing", plural: "things")
            + " said. A shorter window reacts faster to a change of subject; a "
            + "longer one waits to be sure the subject really changed."
    }
}
