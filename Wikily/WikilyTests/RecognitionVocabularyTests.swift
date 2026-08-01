import Foundation
import Testing
@testable import Wikily

/// Covers the vocabulary handed to `SpeechAnalyzer` as contextual strings.
struct RecognitionVocabularyTests {

    private static var vaultPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("wiki-sample")
            .path
    }

    @Test func vocabularyIncludesTitlesAliasesAndTags() throws {
        let index = WikiIndexBuilder.build(
            try WikiScanner.scan(directory: Self.vaultPath).files.map(MarkdownParser.parse)
        )
        let vocabulary = index.recognitionVocabulary()
        let lowercased = vocabulary.map { $0.lowercased() }

        #expect(lowercased.contains { $0.contains("becky") })
        #expect(lowercased.contains { $0.contains("oauth") })
        #expect(!vocabulary.isEmpty)
    }

    @Test func vocabularyIsDeduplicatedAndDropsVeryShortTokens() {
        let document = MarkdownParser.parse(RawWikiFile(
            path: "/wiki/dupes.md",
            name: "dupes",
            content: """
            ---
            title: "Widget"
            aliases: ["widget", "WIDGET", "hi"]
            tags: [widget, ok]
            ---

            # Widget
            """
        ))
        let vocabulary = WikiIndexBuilder.build([document]).recognitionVocabulary()

        // Case-insensitive dedup: one "widget", not four.
        #expect(vocabulary.filter { $0.lowercased() == "widget" }.count == 1)
        // Two-character entries are noise as recognition hints.
        #expect(!vocabulary.contains { $0.count < 3 })
    }

    @Test func vocabularyIsCappedSoTheBiasIsNotDiluted() {
        let documents = (0..<500).map { number in
            MarkdownParser.parse(RawWikiFile(
                path: "/wiki/page-\(number).md",
                name: "page-\(number)",
                content: "# Page Number \(number)\n\nBody text."
            ))
        }
        let vocabulary = WikiIndexBuilder.build(documents).recognitionVocabulary(limit: 50)
        #expect(vocabulary.count == 50)
    }

    @Test func emptyVaultYieldsNoVocabulary() {
        #expect(WikiIndex.empty.recognitionVocabulary().isEmpty)
    }
}
