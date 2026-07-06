-- Wikily local wiki engine persistence (Tech Spec §5.7).
--
-- The parsed wiki index is cached here so that re-scans are incremental
-- (only files whose content_hash changed are re-parsed/re-indexed) and the
-- overlay is ready across restarts without a full rescan. Everything is
-- strictly local — no wiki content ever leaves the machine (§4.2).

-- One row per markdown file in the configured vault.
CREATE TABLE IF NOT EXISTS wiki_files (
    id TEXT PRIMARY KEY,            -- absolute file path (stable doc id)
    path TEXT NOT NULL,
    content_hash TEXT NOT NULL,     -- change-detection fingerprint from the scanner
    title TEXT NOT NULL,
    status TEXT,
    source_url TEXT,                -- e.g. a Notion deep link from frontmatter
    frontmatter_json TEXT NOT NULL, -- serialized parsed WikiDocument (index cache)
    updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_wiki_files_hash ON wiki_files(content_hash);

-- Section-level chunks (forward-compat: the MVP indexes at the document level;
-- this table lets a future section-granular / neural-embedding path land
-- without another migration).
CREATE TABLE IF NOT EXISTS wiki_chunks (
    id TEXT PRIMARY KEY,
    file_id TEXT NOT NULL,
    section_anchor TEXT,
    text TEXT NOT NULL,
    char_range TEXT,
    FOREIGN KEY (file_id) REFERENCES wiki_files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_wiki_chunks_file_id ON wiki_chunks(file_id);

-- Embedding vectors per chunk (forward-compat placeholder for a fastembed/ONNX
-- path; the MVP uses an in-memory TF-IDF cosine index).
CREATE TABLE IF NOT EXISTS wiki_embeddings (
    chunk_id TEXT PRIMARY KEY,
    dim INTEGER NOT NULL,
    vector BLOB NOT NULL,
    FOREIGN KEY (chunk_id) REFERENCES wiki_chunks(id) ON DELETE CASCADE
);

-- Local-only engagement telemetry for the relevance KPI (§7). Stores only a
-- hash of the transcript window plus the matched file id and score — never the
-- raw transcript. `clicked` flips to 1 when the rep copies/opens a card.
CREATE TABLE IF NOT EXISTS match_log (
    id TEXT PRIMARY KEY,
    ts INTEGER NOT NULL,
    window_text_hash TEXT NOT NULL,
    matched_file_id TEXT,
    score REAL NOT NULL,
    clicked INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_match_log_ts ON match_log(ts DESC);
