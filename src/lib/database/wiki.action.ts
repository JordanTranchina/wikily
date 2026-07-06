// Wikily wiki-index persistence + local-only match telemetry (Tech Spec §5.7 / §7).
//
// Two responsibilities, both strictly on-device:
//   1. Cache the parsed wiki index (keyed by content hash) so re-scans are
//      incremental and the overlay survives restarts without a full rescan.
//   2. Record engagement telemetry for the relevance KPI — storing only a hash
//      of the transcript window plus the matched file id/score, never raw text.

import { getDatabase } from "./config";
import { WikiDocument } from "@/lib/wiki";

/** A persisted wiki file row: its change-hash + the serialized parsed document. */
export interface CachedWikiFile {
  hash: string;
  doc: WikiDocument;
}

interface WikiFileRow {
  id: string;
  content_hash: string;
  frontmatter_json: string;
}

/**
 * Load the cached parsed index, keyed by file path (== doc id). Callers reuse a
 * cached doc when the scanner reports an unchanged content hash, skipping the
 * parse/index work for that file.
 */
export async function loadWikiCache(): Promise<Map<string, CachedWikiFile>> {
  const out = new Map<string, CachedWikiFile>();
  try {
    const db = await getDatabase();
    const rows = await db.select<WikiFileRow[]>(
      "SELECT id, content_hash, frontmatter_json FROM wiki_files"
    );
    for (const row of rows) {
      try {
        out.set(row.id, {
          hash: row.content_hash,
          doc: JSON.parse(row.frontmatter_json) as WikiDocument,
        });
      } catch {
        // Skip a corrupt cache row; it will be re-parsed and overwritten.
      }
    }
  } catch (error) {
    // A missing/locked DB just means "no cache" — the caller re-parses fresh.
    console.error("Failed to load wiki cache:", error);
  }
  return out;
}

/**
 * Persist the current index. Upserts one row per document (storing the parsed
 * doc as JSON) and prunes rows for files no longer in the vault.
 */
export async function persistWikiCache(
  entries: { hash: string; doc: WikiDocument }[]
): Promise<void> {
  try {
    const db = await getDatabase();
    const now = Date.now();
    const keepIds: string[] = [];

    for (const { hash, doc } of entries) {
      keepIds.push(doc.id);
      const sourceUrl = doc.links[0]?.url ?? null;
      await db.execute(
        `INSERT INTO wiki_files
           (id, path, content_hash, title, status, source_url, frontmatter_json, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           path = excluded.path,
           content_hash = excluded.content_hash,
           title = excluded.title,
           status = excluded.status,
           source_url = excluded.source_url,
           frontmatter_json = excluded.frontmatter_json,
           updated_at = excluded.updated_at`,
        [
          doc.id,
          doc.id,
          hash,
          doc.title,
          doc.status ?? null,
          sourceUrl,
          JSON.stringify(doc),
          now,
        ]
      );
    }

    // Prune deleted files so the cache mirrors the vault.
    if (keepIds.length > 0) {
      const placeholders = keepIds.map(() => "?").join(",");
      await db.execute(
        `DELETE FROM wiki_files WHERE id NOT IN (${placeholders})`,
        keepIds
      );
    } else {
      await db.execute("DELETE FROM wiki_files");
    }
  } catch (error) {
    // Persistence is a best-effort cache; matching still works in-memory.
    console.error("Failed to persist wiki cache:", error);
  }
}

/**
 * Record that a proactive card fired. Returns the row id (used to mark a later
 * click), or null if telemetry is disabled/unavailable. Stores only the window
 * hash — never the transcript text.
 */
export async function logMatch(params: {
  windowTextHash: string;
  matchedFileId: string;
  score: number;
}): Promise<string | null> {
  try {
    const db = await getDatabase();
    const id = `match_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    await db.execute(
      "INSERT INTO match_log (id, ts, window_text_hash, matched_file_id, score, clicked) VALUES (?, ?, ?, ?, ?, 0)",
      [id, Date.now(), params.windowTextHash, params.matchedFileId, params.score]
    );
    return id;
  } catch (error) {
    console.error("Failed to log match:", error);
    return null;
  }
}

/** Flip a logged match to "clicked" when the rep copies/opens the card. */
export async function markMatchClicked(id: string): Promise<void> {
  try {
    const db = await getDatabase();
    await db.execute("UPDATE match_log SET clicked = 1 WHERE id = ?", [id]);
  } catch (error) {
    console.error("Failed to mark match clicked:", error);
  }
}
