import Foundation

/// Drives the overlay from a scripted call, with no audio and no recording.
///
/// The HUD is otherwise unverifiable without starting a real capture, and
/// "record a call to check the padding" is not an acceptable development loop —
/// nor something a user should have to consent to for a layout change.
///
/// Deliberately runs through the *real* pipeline: it builds a real index from a
/// real vault and pushes segments through `CallSession.ingest(_:)`, the same
/// entry point the transcriber uses. So what it shows on screen is what a live
/// call with those words would show, not a hand-assembled mock.
///
/// Follows the `--capture-diagnostics` precedent in `CaptureDiagnostics`: a
/// launch-argument mode that ships in the product because the thing it exercises
/// cannot be reached any other way.
enum OverlayPreview {

    static let argument = "--overlay-preview"

    /// The vault to index, from `--overlay-preview <path>`, or the bundled sample.
    static func requestedVaultPath(from arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        guard arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("--")
        else { return "" }
        return (arguments[index + 1] as NSString).expandingTildeInPath
    }

    /// A short scripted call: small talk that must *not* trigger a card, then the
    /// question that must.
    static let script = [
        TranscriptSegment(text: "Hey, thanks for hopping on.", source: .microphone, startTime: 0),
        TranscriptSegment(text: "No problem at all, how's your week going?", source: .system, startTime: 3),
        TranscriptSegment(text: "Not bad. So what did you want to go over?", source: .microphone, startTime: 7),
        TranscriptSegment(text: "I wanted an update on the Becky promotion.", source: .system, startTime: 11),
    ]

    @MainActor
    static func run(session: CallSession, vaultPath: String) async {
        if !vaultPath.isEmpty {
            await session.loadWiki(directory: vaultPath)
        }
        session.enterPreviewListening()

        for segment in script {
            session.ingest(segment)
            session.noteSpeechStarted()
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}
