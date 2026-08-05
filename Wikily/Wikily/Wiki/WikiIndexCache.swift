import Foundation
import OSLog

/// Caches parsed wiki documents between launches so a re-scan only pays for what
/// changed.
///
/// The cost this removes is markdown parsing, not disk I/O — `WikiScanner` has
/// to read every file anyway to fingerprint it. That is still the expensive half
/// on a real vault: frontmatter, headings, links and body extraction per page,
/// against a scan that is mostly `readfile`. Re-indexing can be triggered
/// mid-call from the menu bar, so "cheap enough not to think about" is a
/// requirement rather than a nicety.
///
/// The Tauri build did this in SQLite. JSON in Application Support is the right
/// trade here: the whole cache is read and written as a unit, there are no
/// queries, and a corrupt file costs one re-parse rather than a migration story.
///
/// Correctness rests entirely on `RawWikiFile.hash` (`StableHash.content`, FNV-1a
/// over the file's bytes) being stable across processes. It deliberately is not
/// mtime-based: mtime changes when a sync client rewrites an identical file, and
/// does not change when a file is restored from backup with an older stamp.
struct WikiIndexCache: Sendable {

    private static let logger = Logger(subsystem: "com.wikily.Wikily", category: "WikiIndexCache")

    /// Bumped whenever `WikiDocument`'s shape or the parser's output changes.
    /// A mismatch discards the whole cache, which is the only safe response —
    /// a document parsed by an older build may be missing a field the matcher
    /// now depends on, and nothing in the file would reveal that.
    static let currentVersion = 1

    let fileURL: URL

    init(fileURL: URL = WikiIndexCache.defaultFileURL()) {
        self.fileURL = fileURL
    }

    // MARK: - Stored shape

    struct Entry: Sendable, Equatable, Codable {
        /// Absolute path, matching `WikiDocument.id`.
        var path: String
        /// Content fingerprint at the time the document was parsed.
        var hash: String
        var document: WikiDocument
    }

    struct Snapshot: Sendable, Equatable, Codable {
        var version: Int = WikiIndexCache.currentVersion
        /// The vault these entries came from. A different folder invalidates
        /// everything: paths are absolute, so entries from another vault could
        /// never match anyway, and keeping them just grows the file forever.
        var vaultPath: String
        var entries: [Entry]

        static let empty = Snapshot(vaultPath: "", entries: [])

        /// Entries by path, for hash lookup during reconciliation.
        var byPath: [String: Entry] {
            Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// What a reconciliation did, in enough detail to log and to assert on.
    struct Reconciliation: Sendable, Equatable {
        /// Parsed documents for every scanned file, in scan order.
        var documents: [WikiDocument]
        var snapshot: Snapshot
        /// Files whose cached parse was reused unchanged.
        var reusedPaths: [String]
        /// Files parsed now: new, or changed since the cache was written.
        var parsedPaths: [String]
        /// Cached files that are no longer in the vault.
        var prunedPaths: [String]
    }

    // MARK: - Reconciliation

    /// Decide, per scanned file, whether to reuse the cached parse or redo it.
    ///
    /// Pure and static so the reuse/prune rules can be tested against a handful
    /// of `RawWikiFile` values without a filesystem, a vault, or a real parser.
    ///
    /// A file with a `nil` hash is always re-parsed. That only happens when a
    /// caller built `RawWikiFile`s by hand, and treating "no fingerprint" as
    /// "unchanged" would serve stale text with no way to notice.
    static func reconcile(
        scanned: [RawWikiFile],
        vaultPath: String,
        cached: Snapshot,
        parse: (RawWikiFile) -> WikiDocument = MarkdownParser.parse
    ) -> Reconciliation {
        let reusable = cached.vaultPath == vaultPath && cached.version == currentVersion
            ? cached.byPath
            : [:]

        var documents: [WikiDocument] = []
        var entries: [Entry] = []
        var reusedPaths: [String] = []
        var parsedPaths: [String] = []
        var survivingPaths = Set<String>()

        documents.reserveCapacity(scanned.count)
        entries.reserveCapacity(scanned.count)

        for file in scanned {
            survivingPaths.insert(file.path)

            if let hash = file.hash,
               let entry = reusable[file.path],
               entry.hash == hash {
                documents.append(entry.document)
                entries.append(entry)
                reusedPaths.append(file.path)
                continue
            }

            let document = parse(file)
            documents.append(document)
            entries.append(
                Entry(path: file.path, hash: file.hash ?? "", document: document)
            )
            parsedPaths.append(file.path)
        }

        // Anything the cache knew about that the scan no longer sees. Dropping
        // these is the entire reason the cache does not grow without bound as a
        // vault is reorganised.
        let prunedPaths = reusable.keys.filter { !survivingPaths.contains($0) }.sorted()

        return Reconciliation(
            documents: documents,
            snapshot: Snapshot(vaultPath: vaultPath, entries: entries),
            reusedPaths: reusedPaths,
            parsedPaths: parsedPaths,
            prunedPaths: prunedPaths
        )
    }

    // MARK: - End to end

    /// Scan a folder and build its index, reusing cached parses where possible.
    ///
    /// The one entry point callers need. Synchronous and blocking — it does real
    /// disk work, so run it off the main actor.
    static func buildIndex(
        directory path: String,
        cache: WikiIndexCache = WikiIndexCache()
    ) throws -> WikiIndex {
        let scan = try WikiScanner.scan(directory: path)
        let result = cache.reconcile(scanned: scan.files, vaultPath: path)
        return WikiIndexBuilder.build(result.documents)
    }

    /// Load, reconcile against `scanned`, and write the new snapshot back.
    ///
    /// The write is best-effort: failing to persist the cache costs a slower
    /// next launch, which is not worth failing an index over.
    func reconcile(scanned: [RawWikiFile], vaultPath: String) -> Reconciliation {
        let result = Self.reconcile(
            scanned: scanned,
            vaultPath: vaultPath,
            cached: load()
        )
        save(result.snapshot)

        Self.logger.info("""
            Wiki cache: reused \(result.reusedPaths.count, privacy: .public), \
            parsed \(result.parsedPaths.count, privacy: .public), \
            pruned \(result.prunedPaths.count, privacy: .public)
            """)
        return result
    }

    // MARK: - Disk

    /// The cache on disk, or an empty snapshot for anything unreadable.
    ///
    /// Every failure collapses to "no cache": a missing file on first run, a
    /// truncated write after a crash, and a snapshot from an older `WikiDocument`
    /// all have the same correct response, which is to parse everything again.
    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == Self.currentVersion
        else {
            Self.logger.info("Discarding unreadable or outdated wiki cache")
            return .empty
        }
        return snapshot
    }

    @discardableResult
    func save(_ snapshot: Snapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic: a half-written cache read on the next launch would decode
            // into garbage or, worse, a valid prefix.
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
            return true
        } catch {
            Self.logger.error("""
                Could not write wiki cache: \(error.localizedDescription, privacy: .public)
                """)
            return false
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// `~/Library/Application Support/com.wikily.Wikily/wiki-index-cache.json`.
    ///
    /// Application Support rather than Caches: rebuilding this is cheap but not
    /// free, and the OS is free to evict Caches at any time — including between
    /// choosing a folder and starting a call.
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.wikily.Wikily",
                isDirectory: true
            )
            .appendingPathComponent("wiki-index-cache.json")
    }
}
