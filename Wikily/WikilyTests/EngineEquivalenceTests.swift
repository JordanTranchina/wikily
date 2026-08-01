import Foundation
import Testing
@testable import Wikily

/// Proves the Swift port produces the *same* results as the TypeScript engine
/// it replaces, rather than merely plausible ones.
///
/// The expected values below were produced by running the original
/// `src/lib/wiki/{parser,index-engine,match-engine}.ts` over the repository's
/// real `wiki-sample/` vault. Scores are compared to six decimal places, so any
/// drift in tokenisation, field weighting, IDF smoothing, vector normalisation
/// or entity boosting fails here immediately.
///
/// This suite is the reason the port can be trusted. When `src/` is deleted in
/// the cutover commit these numbers become the only remaining record of the
/// original engine's behaviour, which is exactly why they are pinned as
/// literals rather than regenerated at test time.
struct EngineEquivalenceTests {

    struct ExpectedResult {
        let fileName: String
        let score: Double
    }

    struct Scenario {
        let transcript: String
        let expected: [ExpectedResult]
    }

    static let scenarios: [Scenario] = [
        Scenario(
            transcript: "Hey, quick question — where did we land on the Becky promotion?",
            expected: [
                ExpectedResult(fileName: "Project- Becky Promotion Campaign.md", score: 0.941202),
                ExpectedResult(fileName: "Billing and Invoices.md", score: 0.027683),
                ExpectedResult(fileName: "Password Reset Flow.md", score: 0.026231),
            ]
        ),
        Scenario(
            transcript: "We are having trouble setting up the OAuth redirect URI for our Sandbox environment.",
            expected: [
                ExpectedResult(fileName: "OAuth Redirect URI (Sandbox).md", score: 1),
            ]
        ),
        Scenario(
            transcript: "The customer wants to know how to update their payment method on the invoice.",
            expected: [
                ExpectedResult(fileName: "Billing and Invoices.md", score: 0.722725),
                ExpectedResult(fileName: "Password Reset Flow.md", score: 0.119511),
                ExpectedResult(fileName: "OAuth Redirect URI (Sandbox).md", score: 0.010058),
            ]
        ),
        Scenario(
            transcript: "They keep hitting a rate limit on the API, what are the actual numbers?",
            expected: [
                ExpectedResult(fileName: "API Rate Limits.md", score: 1),
            ]
        ),
        Scenario(
            transcript: "Walk me through resetting a password for a locked out user.",
            expected: [
                ExpectedResult(fileName: "Password Reset Flow.md", score: 0.423372),
            ]
        ),
        Scenario(
            transcript: "Did you watch the game last night? Crazy weather too.",
            expected: []
        ),
        Scenario(
            transcript: "billing invoice oauth sandbox becky promotion password reset rate limits",
            expected: [
                ExpectedResult(fileName: "OAuth Redirect URI (Sandbox).md", score: 0.778800),
                ExpectedResult(fileName: "API Rate Limits.md", score: 0.762940),
                ExpectedResult(fileName: "Project- Becky Promotion Campaign.md", score: 0.733618),
            ]
        ),
    ]

    /// Absolute path to the repo's `wiki-sample/`, derived from this file's
    /// location so it is independent of the test runner's working directory.
    static var sampleVaultPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // WikilyTests
            .deletingLastPathComponent()    // Wikily
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("wiki-sample")
            .path
    }

    @Test(arguments: scenarios)
    func swiftEngineMatchesTypeScriptEngine(scenario: Scenario) throws {
        let files = try WikiScanner.scan(directory: Self.sampleVaultPath).files
        let index = WikiIndexBuilder.build(files.map(MarkdownParser.parse))

        let actual = WikiMatcher.match(
            index: index,
            transcript: scenario.transcript,
            options: .init(topK: 3)
        )

        #expect(
            actual.count == scenario.expected.count,
            "result count diverged for: \(scenario.transcript)"
        )

        for (actualMatch, expected) in zip(actual, scenario.expected) {
            let actualName = URL(fileURLWithPath: actualMatch.document.id).lastPathComponent
            #expect(
                actualName == expected.fileName,
                "ranking diverged for: \(scenario.transcript)"
            )
            #expect(
                abs(actualMatch.score - expected.score) < 1e-6,
                """
                score diverged for "\(expected.fileName)" on: \(scenario.transcript)
                  TypeScript: \(expected.score)
                  Swift:      \(actualMatch.score)
                """
            )
        }
    }
}

extension EngineEquivalenceTests.Scenario: CustomTestStringConvertible {
    var testDescription: String { transcript }
}
