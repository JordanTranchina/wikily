import Foundation

/// Parses raw markdown (Obsidian/Karpathy-style wiki pages) into structured
/// `WikiDocument`s.
///
/// Port of `src/lib/wiki/parser.ts`. Deliberately dependency-free: a small
/// YAML-ish frontmatter reader plus markdown heuristics tuned for the "compiled
/// wiki" the spec assumes — clear titles, status lines, summaries, cross-links.
/// It is not a general markdown parser and does not need to be.
///
/// Regexes are built locally rather than held as static properties: `Regex` is
/// not `Sendable`, and literals are compiled at build time so constructing the
/// value per call is cheap.
enum MarkdownParser {

    // MARK: - Entry point

    static func parse(_ file: RawWikiFile) -> WikiDocument {
        var content = file.content.replacingOccurrences(of: "\r\n", with: "\n")
        var frontmatter: [String: FrontmatterValue] = [:]

        let frontmatterPattern = #/\A---[ \t]*\n([\s\S]*?)\n---[ \t]*\n?/#
        if let match = content.firstMatch(of: frontmatterPattern) {
            frontmatter = parseFrontmatter(String(match.output.1))
            content = String(content[match.range.upperBound...])
        }

        let lines = content.components(separatedBy: "\n")

        // Title: frontmatter > first H1 > filename.
        var title = frontmatter["title"]?.singleValue ?? ""
        if title.isEmpty,
           let h1 = lines.first(where: { $0.firstMatch(of: #/^#[ \t]+/#) != nil }) {
            title = h1.replacing(#/^#[ \t]+/#, with: "").trimmed
        }
        if title.isEmpty { title = file.name }

        let headings = lines
            .filter { $0.firstMatch(of: #/^#{1,6}[ \t]+/#) != nil }
            .map { $0.replacing(#/^#{1,6}[ \t]+/#, with: "").trimmed }

        // Status / latest update / blocker: frontmatter, else a labelled body line.
        let status = frontmatter["status"]?.singleValue.nonEmpty
            ?? findLabelledLine(lines, labels: ["status"])
        let latestUpdate = frontmatter["latest_update"]?.singleValue.nonEmpty
            ?? frontmatter["latest update"]?.singleValue.nonEmpty
            ?? findLabelledLine(lines, labels: ["latest update", "update", "latest"])
        let blocker = frontmatter["blocker"]?.singleValue.nonEmpty
            ?? findLabelledLine(lines, labels: ["key blocker", "blocker", "blockers"])

        // Summary: frontmatter, else the first substantive paragraph line.
        var summary = frontmatter["summary"]?.singleValue.nonEmpty
            ?? frontmatter["description"]?.singleValue.nonEmpty
            ?? ""
        if summary.isEmpty {
            for line in lines {
                let trimmed = line.trimmed
                if trimmed.isEmpty { continue }
                if trimmed.firstMatch(of: #/^#{1,6}[ \t]+/#) != nil { continue }
                if trimmed.firstMatch(of: #/^[-*][ \t]/#) != nil { continue }
                if trimmed.hasPrefix(">") { continue }
                summary = toPlainText(trimmed)
                break
            }
        }
        summary = String(summary.prefix(400))

        // Tags: frontmatter plus inline `#tags`, de-duplicated, order preserved.
        var tags = OrderedUnique<String>()
        for tag in frontmatter["tags"].arrayValue {
            tags.insert(tag.replacing(#/^#/#, with: ""))
        }
        for match in content.matches(of: #/(?:^|\s)#([a-zA-Z][\w\/-]+)/#) {
            tags.insert(String(match.output.1))
        }

        let aliases = frontmatter["aliases"].arrayValue.isEmpty
            ? frontmatter["alias"].arrayValue
            : frontmatter["aliases"].arrayValue

        // Links: markdown links in the body, plus explicit frontmatter URLs.
        var links: [WikiLink] = []
        for match in content.matches(of: #/\[([^\]]+)\]\(([^)]+)\)/#) {
            let label = String(match.output.1).trimmed
            let url = String(match.output.2).trimmed
            if url.firstMatch(of: #/^https?:\/\//#) != nil {
                links.append(WikiLink(label: label, url: url))
            }
        }
        // Frontmatter link fields jump the queue — they are the canonical
        // "open the real page" target for a card.
        for key in ["notion", "url", "link"] {
            guard let value = frontmatter[key]?.singleValue.nonEmpty,
                  value.firstMatch(of: #/^https?:\/\//#) != nil else { continue }
            let label = key == "notion" ? "Open Notion ↗" : "Open Link ↗"
            links.insert(WikiLink(label: label, url: value), at: 0)
        }

        return WikiDocument(
            id: file.path,
            title: title,
            summary: summary,
            status: status?.nonEmpty,
            latestUpdate: latestUpdate?.nonEmpty,
            blocker: blocker?.nonEmpty,
            tags: tags.values,
            aliases: aliases,
            links: dedupeLinks(links),
            headings: headings,
            body: toPlainText(content)
        )
    }

    // MARK: - Frontmatter

    /// A frontmatter value is either a scalar or a list.
    enum FrontmatterValue: Equatable {
        case scalar(String)
        case list([String])

        /// The scalar form, or "" for a list. Mirrors the TypeScript casts.
        var singleValue: String {
            if case .scalar(let value) = self { return value }
            return ""
        }

        /// The list form. A scalar is split on commas, matching `asArray`.
        var arrayValue: [String] {
            switch self {
            case .list(let values):
                return values.filter { !$0.isEmpty }
            case .scalar(let value):
                return value
                    .components(separatedBy: ",")
                    .map(\.trimmed)
                    .filter { !$0.isEmpty }
            }
        }
    }

    /// Parse a tiny subset of YAML: `key: value`, inline `[a, b]` lists, and
    /// block `- item` lists. Anything richer is out of scope by design.
    static func parseFrontmatter(_ raw: String) -> [String: FrontmatterValue] {
        var out: [String: FrontmatterValue] = [:]
        var currentListKey: String?

        for line in raw.components(separatedBy: "\n") {
            if line.trimmed.isEmpty { continue }

            // Block list item: "  - value"
            if let item = line.firstMatch(of: #/^\s*-\s+(.+)$/#), let key = currentListKey {
                var values = out[key].arrayValue
                values.append(stripQuotes(String(item.output.1).trimmed))
                out[key] = .list(values)
                continue
            }

            guard let pair = line.firstMatch(of: #/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/#) else {
                continue
            }
            let key = String(pair.output.1).trimmed.lowercased()
            let value = String(pair.output.2).trimmed

            if value.isEmpty {
                // Start of a block list.
                currentListKey = key
                out[key] = .list([])
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                out[key] = .list(
                    inner.components(separatedBy: ",")
                        .map { stripQuotes($0.trimmed) }
                        .filter { !$0.isEmpty }
                )
                currentListKey = nil
            } else {
                out[key] = .scalar(stripQuotes(value))
                currentListKey = nil
            }
        }
        return out
    }

    private static func stripQuotes(_ s: String) -> String {
        s.replacing(#/^["']|["']$/#, with: "")
    }

    // MARK: - Body heuristics

    /// Convert markdown into roughly plain text for indexing.
    ///
    /// The replacement order is inherited verbatim from the TypeScript so the
    /// resulting token stream — and therefore every index weight — matches.
    /// Note the image rule runs *after* the link rule has already consumed the
    /// `[alt](url)` portion of an image; that quirk is preserved intentionally
    /// rather than "fixed", since changing it would silently shift scores.
    static func toPlainText(_ markdown: String) -> String {
        var text = markdown
        text = text.replacing(#/\[([^\]]+)\]\(([^)]+)\)/#) { String($0.output.1) }
        text = text.replacing(#/\[\[([^\]]+)\]\]/#) { String($0.output.1) }
        text = text.replacing(#/[`*_>#~|]/#, with: " ")
        text = text.replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: " ")
        text = text.replacingOccurrences(of: "\r", with: "")
        return text.trimmed
    }

    /// Find the first `Label: value` line whose label is one we care about.
    ///
    /// Markdown emphasis and list markers are stripped first, so `**Status:**
    /// Blocked` and `- Status: Blocked` both resolve.
    static func findLabelledLine(_ lines: [String], labels: [String]) -> String? {
        for line in lines {
            let cleaned = line.replacing(#/[*_>#`\-]/#, with: "").trimmed
            guard let colon = cleaned.firstIndex(of: ":") else { continue }
            let key = cleaned[..<colon].trimmed.lowercased()
            guard labels.contains(key) else { continue }
            let value = cleaned[cleaned.index(after: colon)...].trimmed
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func dedupeLinks(_ links: [WikiLink]) -> [WikiLink] {
        var seen = Set<String>()
        var out: [WikiLink] = []
        for link in links where seen.insert(link.url).inserted {
            out.append(link)
        }
        return Array(out.prefix(4))
    }
}

// MARK: - Small helpers

/// Insertion-ordered unique collection.
///
/// A plain `Set` would do for indexing, where only membership matters, but tags
/// are also user-visible and their order should be stable across runs.
struct OrderedUnique<Element: Hashable> {
    private var seen = Set<Element>()
    private(set) var values: [Element] = []

    mutating func insert(_ element: Element) {
        guard seen.insert(element).inserted else { return }
        values.append(element)
    }
}

extension StringProtocol {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    /// `nil` when empty, so `??` chains read as "first non-empty source wins".
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Optional where Wrapped == MarkdownParser.FrontmatterValue {
    var arrayValue: [String] { self?.arrayValue ?? [] }
}
