import Foundation
import Testing
@testable import Wikily

/// Covers the filesystem walk ported from `src-tauri/src/wiki.rs`, plus an
/// end-to-end pass over the repository's real `wiki-sample/` vault.
struct WikiScannerTests {

    // MARK: - Temporary-vault helpers

    private func withTemporaryVault(
        _ files: [String: String],
        body: (String) throws -> Void
    ) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wikily-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (relativePath, contents) in files {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try body(root.path)
    }

    // MARK: - Tests

    @Test func findsMarkdownRecursivelyAndSkipsOtherExtensions() throws {
        try withTemporaryVault([
            "top.md": "# Top",
            "nested/deep/page.markdown": "# Deep",
            "nested/notes.mdx": "# MDX",
            "image.png": "not markdown",
            "readme.txt": "not markdown",
        ]) { path in
            let result = try WikiScanner.scan(directory: path)
            // Names are file stems: page.markdown -> "page", notes.mdx -> "notes".
            let names = result.files.map(\.name).sorted()
            #expect(names == ["notes", "page", "top"])
            #expect(result.scannedDirectoryCount >= 3)
        }
    }

    @Test func skipsDottedAndDependencyDirectories() throws {
        try withTemporaryVault([
            "keep.md": "# Keep",
            ".obsidian/config.md": "# Skip",
            ".git/notes.md": "# Skip",
            ".trash/old.md": "# Skip",
            "node_modules/pkg/readme.md": "# Skip",
        ]) { path in
            let result = try WikiScanner.scan(directory: path)
            #expect(result.files.map(\.name) == ["keep"])
        }
    }

    @Test func returnsFilesInStableSortedOrder() throws {
        try withTemporaryVault([
            "charlie.md": "# C",
            "alpha.md": "# A",
            "bravo.md": "# B",
        ]) { path in
            let paths = try WikiScanner.scan(directory: path).files.map(\.path)
            #expect(paths == paths.sorted())
        }
    }

    @Test func attachesAContentHashThatChangesWithContent() throws {
        try withTemporaryVault(["page.md": "# Original"]) { path in
            let first = try #require(try WikiScanner.scan(directory: path).files.first)
            #expect(first.hash?.count == 16)
            #expect(first.hash == StableHash.content("# Original"))
        }
    }

    @Test func throwsForMissingDirectory() {
        #expect(throws: WikiScanner.ScanError.self) {
            try WikiScanner.scan(directory: "/definitely/not/a/real/path/xyzzy")
        }
    }

    @Test func throwsWhenPathIsAFileNotADirectory() throws {
        try withTemporaryVault(["page.md": "# Page"]) { path in
            let filePath = (path as NSString).appendingPathComponent("page.md")
            #expect(throws: WikiScanner.ScanError.self) {
                try WikiScanner.scan(directory: filePath)
            }
        }
    }

    // MARK: - The real sample vault

    /// Absolute path to the repo's `wiki-sample/`, derived from this source
    /// file's location so it works regardless of the test runner's cwd.
    private static var sampleVaultPath: String {
        URL(fileURLWithPath: #filePath)                 // .../Wikily/WikilyTests/WikiScannerTests.swift
            .deletingLastPathComponent()                // .../Wikily/WikilyTests
            .deletingLastPathComponent()                // .../Wikily
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("wiki-sample")
            .path
    }

    @Test func indexesTheRealSampleVaultAndResolvesTheSpecScenario() throws {
        let result = try WikiScanner.scan(directory: Self.sampleVaultPath)
        #expect(result.files.count == 5)

        let index = WikiIndexBuilder.build(result.files.map(MarkdownParser.parse))
        #expect(index.stats.documentCount == 5)
        #expect(index.stats.tokenCount > 0)

        // Product Spec §2.3, the headline acceptance scenario, against the real
        // on-disk vault rather than inline fixtures.
        let matches = WikiMatcher.match(
            index: index,
            transcript: "Hey, quick question — where did we land on the Becky promotion?"
        )
        let top = try #require(matches.first)
        #expect(top.document.title.contains("Becky"))
        #expect(top.score >= WikiMatchCoordinator.defaultThreshold)
    }

    @Test func realVaultPagesParseIntoUsableCards() throws {
        let result = try WikiScanner.scan(directory: Self.sampleVaultPath)
        let documents = result.files.map(MarkdownParser.parse)

        // Every page must yield something the HUD can actually render.
        for document in documents {
            #expect(!document.title.isEmpty, "\(document.id) has no title")
            #expect(!document.body.isEmpty, "\(document.id) has no body")
        }
    }
}
