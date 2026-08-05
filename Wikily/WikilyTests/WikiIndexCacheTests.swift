import Foundation
import Testing
@testable import Wikily

/// Covers the incremental re-scan: what gets reused, what gets re-parsed, and
/// what gets dropped.
///
/// The reuse rules are the kind of thing that fails silently — a cache that
/// serves a stale document does not crash, it just quietly suggests the wrong
/// page for the rest of the vault's life. So the tests assert on *which* files
/// took which path, not merely on the document count.
struct WikiIndexCacheTests {

    // MARK: - Helpers

    private func withTemporaryVault(
        _ files: [String: String],
        _ body: (String, WikiIndexCache) throws -> Void
    ) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wikily-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (name, contents) in files {
            try contents.write(
                to: root.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let cacheFile = root.appendingPathComponent(".cache/index.json")
        try body(root.path, WikiIndexCache(fileURL: cacheFile))
    }

    private func write(_ contents: String, to name: String, in vault: String) throws {
        try contents.write(
            to: URL(fileURLWithPath: vault).appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    private func scan(_ vault: String) throws -> [RawWikiFile] {
        try WikiScanner.scan(directory: vault).files
    }

    private func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Reuse

    @Test func aFirstScanParsesEverythingAndCachesNothingStale() throws {
        try withTemporaryVault([
            "alpha.md": "# Alpha\nAlpha body.",
            "bravo.md": "# Bravo\nBravo body.",
        ]) { vault, cache in
            let result = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            #expect(result.parsedPaths.count == 2)
            #expect(result.reusedPaths.isEmpty)
            #expect(result.prunedPaths.isEmpty)
            #expect(result.documents.count == 2)
        }
    }

    @Test func anUnchangedVaultIsEntirelyReusedOnTheSecondScan() throws {
        try withTemporaryVault([
            "alpha.md": "# Alpha\nAlpha body.",
            "bravo.md": "# Bravo\nBravo body.",
        ]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)
            let second = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            #expect(second.reusedPaths.count == 2)
            #expect(second.parsedPaths.isEmpty)
        }
    }

    @Test func onlyTheChangedFileIsReparsed() throws {
        try withTemporaryVault([
            "alpha.md": "# Alpha\nAlpha body.",
            "bravo.md": "# Bravo\nBravo body.",
            "charlie.md": "# Charlie\nCharlie body.",
        ]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            try write("# Bravo Renamed\nNew body.", to: "bravo.md", in: vault)
            let second = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            #expect(second.parsedPaths.map(name) == ["bravo.md"])
            #expect(second.reusedPaths.map(name).sorted() == ["alpha.md", "charlie.md"])

            // The re-parse has to actually produce the new content, not just be
            // counted as one.
            let bravo = try #require(second.documents.first { $0.id.hasSuffix("bravo.md") })
            #expect(bravo.title == "Bravo Renamed")
        }
    }

    /// Rewriting a file with byte-identical contents changes its modification
    /// date but not its hash, and it must still be reused. This is the whole
    /// reason the cache fingerprints content: a sync client rewriting an
    /// unchanged vault would otherwise invalidate every page in it.
    @Test func rewritingAFileWithIdenticalContentStillReuses() throws {
        try withTemporaryVault(["alpha.md": "# Alpha\nOriginal."]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            try write("# Alpha\nOriginal.", to: "alpha.md", in: vault)
            let second = cache.reconcile(scanned: try scan(vault), vaultPath: vault)
            #expect(second.reusedPaths.map(name) == ["alpha.md"])
            #expect(second.parsedPaths.isEmpty)
        }
    }

    @Test func aNewFileIsParsedWhileTheRestIsReused() throws {
        try withTemporaryVault(["alpha.md": "# Alpha\nBody."]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            try write("# Delta\nBody.", to: "delta.md", in: vault)
            let second = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            #expect(second.parsedPaths.map(name) == ["delta.md"])
            #expect(second.reusedPaths.map(name) == ["alpha.md"])
            #expect(second.documents.count == 2)
        }
    }

    // MARK: - Prune

    @Test func aDeletedFileIsPrunedFromTheCacheAndTheDocuments() throws {
        try withTemporaryVault([
            "alpha.md": "# Alpha\nBody.",
            "bravo.md": "# Bravo\nBody.",
        ]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            try FileManager.default.removeItem(
                at: URL(fileURLWithPath: vault).appendingPathComponent("bravo.md")
            )
            let second = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            #expect(second.prunedPaths.map(name) == ["bravo.md"])
            #expect(second.documents.map(\.title) == ["Alpha"])
            // And it must be gone from disk, or the cache grows forever as a
            // vault is reorganised.
            #expect(cache.load().entries.count == 1)
        }
    }

    // MARK: - Invalidation

    @Test func pointingAtADifferentVaultInvalidatesEverything() throws {
        try withTemporaryVault(["alpha.md": "# Alpha\nBody."]) { vault, cache in
            let scanned = try scan(vault)
            _ = cache.reconcile(scanned: scanned, vaultPath: vault)

            let result = WikiIndexCache.reconcile(
                scanned: scanned,
                vaultPath: "/somewhere/else",
                cached: cache.load()
            )
            #expect(result.reusedPaths.isEmpty)
            #expect(result.parsedPaths.count == 1)
            #expect(result.prunedPaths.isEmpty)
        }
    }

    @Test func aCacheFromAnOlderVersionIsDiscarded() throws {
        try withTemporaryVault(["alpha.md": "# Alpha\nBody."]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            var stale = cache.load()
            stale.version = WikiIndexCache.currentVersion - 1
            cache.save(stale)

            #expect(cache.load().entries.isEmpty)
            let result = cache.reconcile(scanned: try scan(vault), vaultPath: vault)
            #expect(result.parsedPaths.count == 1)
        }
    }

    /// Every failure to read the cache has to collapse to "no cache". A
    /// truncated write after a crash must cost one re-parse, not a launch.
    @Test func aCorruptCacheFileIsTreatedAsEmpty() throws {
        try withTemporaryVault(["alpha.md": "# Alpha\nBody."]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            try FileManager.default.createDirectory(
                at: cache.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{ not json".utf8).write(to: cache.fileURL)

            #expect(cache.load().entries.isEmpty)
            let rebuilt = cache.reconcile(scanned: try scan(vault), vaultPath: vault)
            #expect(rebuilt.parsedPaths.count == 1)
        }
    }

    @Test func aMissingCacheFileIsTreatedAsEmpty() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wikily-absent-\(UUID().uuidString).json")
        #expect(WikiIndexCache(fileURL: missing).load() == .empty)
    }

    /// Only ever produced by a caller building `RawWikiFile`s by hand. Treating
    /// "no fingerprint" as "unchanged" would serve stale text forever.
    @Test func aFileWithNoHashIsAlwaysReparsed() throws {
        let file = RawWikiFile(path: "/vault/a.md", name: "a", content: "# A", hash: nil)
        let cached = WikiIndexCache.Snapshot(
            vaultPath: "/vault",
            entries: [
                WikiIndexCache.Entry(
                    path: "/vault/a.md",
                    hash: "",
                    document: MarkdownParser.parse(file)
                )
            ]
        )

        let result = WikiIndexCache.reconcile(
            scanned: [file],
            vaultPath: "/vault",
            cached: cached
        )
        #expect(result.parsedPaths == ["/vault/a.md"])
        #expect(result.reusedPaths.isEmpty)
    }

    // MARK: - Equivalence with a plain scan

    /// The cache is an optimisation, so a cached build and an uncached one must
    /// be indistinguishable. If they ever diverge, matching quality silently
    /// depends on whether the user has relaunched.
    @Test func aCachedBuildMatchesAFreshOne() throws {
        try withTemporaryVault([
            "alpha.md": "---\ntitle: Alpha\ntags: [one, two]\n---\n# Heading\nBody text.",
            "bravo.md": "# Bravo\nStatus: Active\nMore body.",
        ]) { vault, cache in
            _ = cache.reconcile(scanned: try scan(vault), vaultPath: vault)

            let cached = cache.reconcile(scanned: try scan(vault), vaultPath: vault)
            let fresh = try scan(vault).map(MarkdownParser.parse)

            #expect(cached.reusedPaths.count == 2)
            #expect(cached.documents == fresh)
        }
    }

    @Test func buildIndexProducesTheSameIndexAsAnUncachedBuild() throws {
        try withTemporaryVault([
            "alpha.md": "# Alpha\nAlpha body.",
            "bravo.md": "# Bravo\nBravo body.",
        ]) { vault, cache in
            let index = try WikiIndexCache.buildIndex(directory: vault, cache: cache)
            let expected = WikiIndexBuilder.build(try scan(vault).map(MarkdownParser.parse))

            #expect(index.stats == expected.stats)
            #expect(index.documents == expected.documents)

            // And again, now that the cache is warm.
            let warm = try WikiIndexCache.buildIndex(directory: vault, cache: cache)
            #expect(warm.stats == expected.stats)
            #expect(warm.documents == expected.documents)
        }
    }

    @Test func buildIndexPropagatesAMissingDirectory() {
        #expect(throws: WikiScanner.ScanError.self) {
            try WikiIndexCache.buildIndex(directory: "/definitely/not/here/xyzzy")
        }
    }
}
