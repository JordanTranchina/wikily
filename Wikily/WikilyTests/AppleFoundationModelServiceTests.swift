import FoundationModels
import Foundation
import Testing
@testable import Wikily

/// The on-device backend cannot be made to generate on demand in a test — the
/// model is gated on hardware, an OS toggle, and an asset download none of which
/// a test can arrange. So what is tested is the part that decides what the user
/// is *told*, which is where the real bugs live: `SystemLanguageModel` reports
/// three distinct reasons for being unavailable and they call for three
/// different actions from the user.
///
/// The mapping is a pure function over `SystemLanguageModel.Availability` for
/// exactly this reason, so every branch runs regardless of what this Mac can do.
struct AppleFoundationModelServiceTests {

    @Test func anAvailableModelReportsNoProblem() {
        let state = AppleFoundationModelService.availability(of: .available)
        #expect(state == .available)
        #expect(state.message == nil)
    }

    @Test func anIneligibleDeviceIsToldToUseALocalServerInstead() throws {
        let state = AppleFoundationModelService.availability(of: .unavailable(.deviceNotEligible))
        #expect(!state.isAvailable)
        let message = try #require(state.message)
        #expect(message.contains("doesn't support Apple Intelligence"))
        // The only actionable advice on hardware that will never qualify.
        #expect(message.contains("local model server"))
    }

    @Test func aDisabledToggleNamesThePaneThatTurnsItOn() throws {
        let state = AppleFoundationModelService.availability(
            of: .unavailable(.appleIntelligenceNotEnabled)
        )
        #expect(!state.isAvailable)
        let message = try #require(state.message)
        #expect(message.contains("turned off"))
        #expect(message.contains("System Settings"))
    }

    /// The transient case, and the one most likely to be misread as broken: the
    /// device qualifies and the toggle is on, the assets just aren't down yet.
    @Test func aDownloadingModelSaysItIsTemporary() throws {
        let state = AppleFoundationModelService.availability(of: .unavailable(.modelNotReady))
        #expect(!state.isAvailable)
        let message = try #require(state.message)
        #expect(message.contains("downloading"))
        #expect(message.contains("try again"))
    }

    @Test func everyUnavailableReasonProducesADistinctActionableSentence() {
        let messages: [String] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
        ].compactMap {
            AppleFoundationModelService.availability(of: .unavailable($0)).message
        }

        #expect(messages.count == 3)
        #expect(Set(messages).count == 3, "reasons must not collapse to one sentence")
        for message in messages {
            #expect(message.count > 20, "“\(message)” is too terse to act on")
        }
    }

    // MARK: - Against whatever this machine actually is

    /// Whichever state this Mac is in, the service has to answer without
    /// throwing and without an empty explanation.
    @Test func liveAvailabilityIsAlwaysReportableOnThisMachine() async {
        let service = AppleFoundationModelService()
        let state = await service.availability()

        if state.isAvailable {
            #expect(state.message == nil)
        } else {
            #expect(state.message?.isEmpty == false)
        }
    }

    /// When the model is unavailable, `stream` must fail with the same sentence
    /// the settings screen shows — not with an opaque `assetsUnavailable`.
    ///
    /// Does nothing on a Mac where Apple Intelligence is on, because there the
    /// call would really generate. That is the intended asymmetry: the assertion
    /// is about the degraded path.
    @Test func generatingWhileUnavailableFailsWithTheSameExplanation() async throws {
        let service = AppleFoundationModelService()
        let state = await service.availability()
        guard case .unavailable = state, let expected = state.message else { return }

        var thrown: (any Error)?
        do {
            for try await _ in service.stream(prompt: "hello", systemPrompt: nil) {}
        } catch {
            thrown = error
        }

        let error = try #require(thrown as? ModelServiceError)
        #expect(error == .unavailable(expected))
    }

    @Test func theDescriptorIsStableAndNamesTheBackend() {
        let service = AppleFoundationModelService()
        #expect(service.descriptor == .appleFoundation)
        #expect(service.descriptor.id == "apple")
        #expect(service.descriptor.serverBaseURL == nil)
        #expect(service.descriptor.modelID == nil)
    }
}
