import Foundation

/// A raw markdown file as returned by `WikiScanner`.
///
/// Port of `RawWikiFile` in `src/lib/wiki/types.ts`.
struct RawWikiFile: Sendable, Equatable {
    /// Absolute path on disk. Doubles as the stable document id.
    var path: String
    /// File name without extension, used as a fallback title.
    var name: String
    /// Raw markdown contents.
    var content: String
    /// Stable content fingerprint, used to skip re-parsing unchanged files.
    var hash: String?

    init(path: String, name: String, content: String, hash: String? = nil) {
        self.path = path
        self.name = name
        self.content = content
        self.hash = hash
    }
}

/// A deep link surfaced on a wiki card (e.g. a Notion page).
struct WikiLink: Sendable, Equatable, Codable {
    var label: String
    var url: String
}

/// A parsed and structured wiki document, ready to index.
///
/// Port of `WikiDocument` in `src/lib/wiki/types.ts`. `Codable` because the
/// parsed form is what gets cached to disk between launches, keyed by content
/// hash, so unchanged files skip parsing entirely.
struct WikiDocument: Sendable, Equatable, Codable, Identifiable {
    /// Stable id — the absolute file path.
    var id: String
    /// Display title: frontmatter `title`, else first H1, else filename.
    var title: String
    /// Short summary for the HUD card: frontmatter `summary`, else first paragraph.
    var summary: String
    /// Status string, from frontmatter `status` or a `Status:` line.
    var status: String?
    /// "Latest update" style line, if present.
    var latestUpdate: String?
    /// Known blocker line, if present.
    var blocker: String?
    /// Tags from frontmatter and inline `#tags`.
    var tags: [String]
    /// Alternate names that should resolve to this doc (frontmatter `aliases`).
    var aliases: [String]
    /// Markdown links found in the doc, used as quick links.
    var links: [WikiLink]
    /// Section headings, used to boost relevance.
    var headings: [String]
    /// Full plain-text body, frontmatter and markdown syntax stripped.
    var body: String
}

/// A search hit: a document plus its score and the entities that matched.
struct WikiMatch: Sendable, Equatable, Identifiable {
    var document: WikiDocument
    /// Normalised confidence in `0...1`.
    var score: Double
    /// Entities or phrases from the transcript that matched this document.
    var matchedEntities: [String]

    var id: String { document.id }
}
