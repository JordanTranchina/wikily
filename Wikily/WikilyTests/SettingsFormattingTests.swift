import Foundation
import Testing
@testable import Wikily

/// The derived strings in Settings, and the wizard's step machine.
///
/// Small surface, but it is the part of the settings UI that can be *wrong*
/// rather than merely ugly: a status line that says a model is installed when it
/// isn't sends the user looking for the problem somewhere else entirely.
struct SettingsFormattingTests {

    // MARK: - Counts

    @Test func countsArePluralisedOnTheNumberNotTheWord() {
        #expect(SettingsFormatting.count(0, singular: "page") == "0 pages")
        #expect(SettingsFormatting.count(1, singular: "page") == "1 page")
        #expect(SettingsFormatting.count(2, singular: "page") == "2 pages")
        #expect(SettingsFormatting.count(1, singular: "entry", plural: "entries") == "1 entry")
        #expect(SettingsFormatting.count(3, singular: "entry", plural: "entries") == "3 entries")
    }

    // MARK: - Last indexed

    @Test func neverIndexedSaysSoRatherThanShowingAnEpochDate() {
        #expect(SettingsFormatting.lastIndexed(nil) == "Never indexed")
    }

    @Test func aRecentIndexReadsAsJustNow() {
        let now = Date()
        #expect(SettingsFormatting.lastIndexed(now.addingTimeInterval(-5), now: now)
            == "Indexed just now")
    }

    @Test func anOlderIndexIsDescribedRelatively() {
        let now = Date()
        let text = SettingsFormatting.lastIndexed(now.addingTimeInterval(-7200), now: now)
        #expect(text.hasPrefix("Indexed "))
        #expect(text != "Indexed just now")
    }

    /// A clock that moved backwards would otherwise produce "Indexed in 4
    /// hours", which reads as a bug in the one panel whose job is telling the
    /// user their index is current.
    @Test func aFutureTimestampNeverReadsAsTheFuture() {
        let now = Date()
        let text = SettingsFormatting.lastIndexed(now.addingTimeInterval(14400), now: now)
        #expect(!text.localizedCaseInsensitiveContains(" in "))
    }

    // MARK: - Speech model

    @Test func everySpeechModelStateProducesActionableText() {
        let locale = Locale(identifier: "en_US")

        let notInstalled = SettingsFormatting.speechModel(.notInstalled, locale: locale)
        #expect(notInstalled.localizedCaseInsensitiveContains("can't transcribe"))

        let installed = SettingsFormatting.speechModel(.installed, locale: locale)
        #expect(installed.localizedCaseInsensitiveContains("installed"))
        #expect(installed.localizedCaseInsensitiveContains("this Mac"))

        let failed = SettingsFormatting.speechModel(
            .failed(message: "No space left"),
            locale: locale
        )
        #expect(failed.contains("No space left"))

        let unsupported = SettingsFormatting.speechModel(.unsupported, locale: locale)
        #expect(unsupported.localizedCaseInsensitiveContains("isn't available"))
    }

    /// Zero progress is the state the installer reports the instant a download
    /// starts. "Downloading… 0%" reads as stuck, so it is suppressed.
    @Test func zeroProgressOmitsThePercentage() {
        let locale = Locale(identifier: "en_US")
        #expect(SettingsFormatting.speechModel(.downloading(fraction: 0), locale: locale)
            == "Downloading…")
        #expect(SettingsFormatting.speechModel(.downloading(fraction: 0.42), locale: locale)
            .contains("42"))
    }

    @Test func aMissingLocaleStillProducesASentence() {
        let text = SettingsFormatting.speechModel(.unsupported, locale: nil)
        #expect(text.contains("your language"))
    }

    // MARK: - Availability

    @Test func availabilityCarriesBothReasonAndRecovery() {
        #expect(SettingsFormatting.availability(.available) == "Ready")

        let text = SettingsFormatting.availability(
            .unavailable(reason: "Apple Intelligence is turned off.", recovery: "Turn it on.")
        )
        #expect(text == "Apple Intelligence is turned off. Turn it on.")
    }
}

/// The wizard's navigation, which has to terminate and has to be reachable in
/// both directions.
struct OnboardingStepTests {

    @Test func stepsRunFromTheFolderToTheHandOff() {
        #expect(OnboardingStep.allCases == [.wikiFolder, .speechModel, .done])
        #expect(OnboardingStep.count == 3)
    }

    @Test func positionsAreOneBasedForDisplay() {
        #expect(OnboardingStep.wikiFolder.position == 1)
        #expect(OnboardingStep.done.position == OnboardingStep.count)
    }

    @Test func navigationTerminatesAtBothEnds() {
        #expect(OnboardingStep.wikiFolder.previous == nil)
        #expect(OnboardingStep.done.next == nil)
        #expect(OnboardingStep.wikiFolder.next == .speechModel)
        #expect(OnboardingStep.speechModel.previous == .wikiFolder)
    }

    /// Walking forward from the first step has to reach the last one, or the
    /// wizard has a step nobody can get to.
    @Test func walkingForwardVisitsEveryStep() {
        var visited: [OnboardingStep] = []
        var step: OnboardingStep? = .wikiFolder
        while let current = step, visited.count <= OnboardingStep.count {
            visited.append(current)
            step = current.next
        }
        #expect(visited == OnboardingStep.allCases)
    }

    @Test func everyStepHasCopy() {
        for step in OnboardingStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.subtitle.isEmpty)
        }
    }

    /// The download step is the only one that needs the network, and the copy
    /// has to say what skipping it costs — otherwise a skipped download becomes
    /// a silent app with no explanation.
    @Test func theSpeechStepWarnsThatSkippingBreaksTranscription() {
        let subtitle = OnboardingStep.speechModel.subtitle
        #expect(subtitle.localizedCaseInsensitiveContains("internet"))
        #expect(subtitle.localizedCaseInsensitiveContains("cannot transcribe"))
    }
}
