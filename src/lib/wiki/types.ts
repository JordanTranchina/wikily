// Wikily local wiki engine — shared types.
// The engine is intentionally framework-agnostic (no Tauri/React imports) so it
// can be unit-tested in plain Node and reused across windows.

/** A raw markdown file as returned by the Rust `scan_wiki_directory` command. */
export interface RawWikiFile {
  path: string;
  name: string;
  content: string;
}

/** A deep link surfaced on a wiki card (e.g. a Notion page). */
export interface WikiLink {
  label: string;
  url: string;
}

/** A parsed + structured wiki document, ready to index. */
export interface WikiDocument {
  /** Stable id (absolute file path). */
  id: string;
  /** Display title (frontmatter `title`, first H1, or filename). */
  title: string;
  /** Short summary for the HUD card (frontmatter `summary` or first paragraph). */
  summary: string;
  /** Status string if present (frontmatter `status` or a `Status:` line). */
  status?: string;
  /** "Latest update" style line if present. */
  latestUpdate?: string;
  /** Known blocker line if present. */
  blocker?: string;
  /** Tags from frontmatter and inline `#tags`. */
  tags: string[];
  /** Alternate names that should resolve to this doc (frontmatter `aliases`). */
  aliases: string[];
  /** Markdown links found in the doc (used as quick links). */
  links: WikiLink[];
  /** Section headings, used to boost relevance. */
  headings: string[];
  /** Full plain-text body (frontmatter + markdown syntax stripped). */
  body: string;
}

/** A search hit: a document plus its match score and the terms that hit. */
export interface WikiMatch {
  document: WikiDocument;
  /** Normalised confidence in [0, 1]. */
  score: number;
  /** Entities / phrases from the transcript that matched this doc. */
  matchedEntities: string[];
}

/** Pre-computed search index over a set of documents. */
export interface WikiIndex {
  documents: WikiDocument[];
  /** Inverse document frequency per token. */
  idf: Record<string, number>;
  /** Normalised tf-idf vector per document id. */
  vectors: Record<string, Record<string, number>>;
  /** Maps lowercased entity/title/alias/tag phrases to document ids. */
  entityMap: Record<string, string[]>;
  stats: {
    documentCount: number;
    tokenCount: number;
  };
}
