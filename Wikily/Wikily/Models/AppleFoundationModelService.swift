import Foundation
import FoundationModels
import OSLog

/// The zero-setup backend: Apple's on-device foundation model.
///
/// This is what makes the product's core claim true for a user who installs the
/// app and does nothing else. No download, no server, no configuration — but
/// also no guarantee, because the model is gated on hardware, on an OS toggle,
/// and on an asset download that happens on Apple's schedule. Roughly half the
/// work in this file is turning that gating into sentences a user can act on
/// rather than an opaque failure.
///
/// A session is created per request rather than held across the call. The
/// service is stateless by design: each suggestion the HUD asks for is
/// independent, and a long-lived session would accumulate transcript context
/// until it hit `exceededContextWindowSize` mid-call — the worst possible time.
/// If multi-turn is ever wanted, it belongs in a separate conversational type,
/// not smuggled into this one.
final class AppleFoundationModelService: LanguageModelService {

    private let logger = Logger(
        subsystem: "com.wikily.Wikily",
        category: "AppleFoundationModelService"
    )

    let descriptor = ModelDescriptor.appleFoundation

    /// Caps the answer length.
    ///
    /// Was `nil` — "truncation is a product decision, the HUD should set it" —
    /// but nothing ever did, so the model had no ceiling at all. That surfaced
    /// as a real bug: asked to recap a call with nothing transcribed yet, the
    /// on-device model repeated an invented bullet point hundreds of times
    /// rather than admitting there was nothing to recap, and kept generating
    /// for as long as it was allowed to. 400 tokens is generous for a card
    /// meant to hold a few sentences and cheap insurance against the next
    /// prompt that trips the same failure mode. `AskSession.maximumAnswerCharacters`
    /// is the second line of defense, independent of whether this backend
    /// honours the request at all.
    private let maximumResponseTokens: Int?

    /// Low by default: this model's job is to summarise and answer from wiki
    /// context, where invention is the failure mode. `GenerationOptions` leaves
    /// this `nil` (model default) if not set, which samples more freely than we
    /// want for grounded output.
    private let temperature: Double?

    init(maximumResponseTokens: Int? = 400, temperature: Double? = 0.3) {
        self.maximumResponseTokens = maximumResponseTokens
        self.temperature = temperature
    }

    func availability() async -> ModelAvailability {
        Self.availability(of: SystemLanguageModel.default.availability)
    }

    /// Split out from `availability()` so the mapping is testable on machines
    /// where the real answer is fixed — CI, and any Mac without Apple
    /// Intelligence, where `SystemLanguageModel.default` will only ever report
    /// one of these cases.
    static func availability(
        of raw: SystemLanguageModel.Availability
    ) -> ModelAvailability {
        switch raw {
        case .available:
            return .available

        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(
                    reason: "This Mac doesn't support Apple Intelligence.",
                    recovery: "Choose a local model server instead."
                )
            case .appleIntelligenceNotEnabled:
                return .unavailable(
                    reason: "Apple Intelligence is turned off.",
                    recovery: "Turn it on in System Settings › Apple Intelligence & Siri."
                )
            case .modelNotReady:
                return .unavailable(
                    reason: "The on-device model is still downloading.",
                    recovery: "This finishes in the background; try again shortly."
                )
            @unknown default:
                // A reason added by a future OS. Saying "unavailable, reason
                // unknown" is honest; inventing a specific cause is not.
                return .unavailable(
                    reason: "Apple Intelligence isn't available on this Mac right now.",
                    recovery: "Choose a local model server instead."
                )
            }

        @unknown default:
            return .unavailable(
                reason: "Apple Intelligence reported a state this version of Wikily "
                    + "doesn't recognise.",
                recovery: "Choose a local model server instead."
            )
        }
    }

    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        let logger = self.logger
        let options = GenerationOptions(
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Checked here rather than only in `availability()` because the
                // state can change between the two — the user can toggle Apple
                // Intelligence off mid-call. Failing with the same sentence the
                // settings screen shows beats failing with `assetsUnavailable`.
                let state = Self.availability(of: SystemLanguageModel.default.availability)
                guard case .available = state else {
                    continuation.finish(
                        throwing: ModelServiceError.unavailable(
                            state.message ?? "Apple Intelligence isn't available."
                        )
                    )
                    return
                }

                do {
                    let session = LanguageModelSession(instructions: systemPrompt)

                    // Snapshots are cumulative — `content` is the whole answer so
                    // far, not the newest token. Diffing them is what turns this
                    // into the append-only stream the protocol promises.
                    var deltas = CumulativeTextDeltas()

                    for try await snapshot in session.streamResponse(
                        to: prompt,
                        options: options
                    ) {
                        if let delta = deltas.delta(for: snapshot.content) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    // The consumer walked away (card dismissed, call ended).
                    // Not a failure worth surfacing.
                    continuation.finish()
                } catch {
                    logger.error("""
                        On-device generation failed: \
                        \(error.localizedDescription, privacy: .public)
                        """)
                    continuation.finish(throwing: error)
                }
            }

            // Without this, abandoning the stream leaves the model generating
            // tokens nobody will read — on a device where that competes with
            // live transcription for the neural engine.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
