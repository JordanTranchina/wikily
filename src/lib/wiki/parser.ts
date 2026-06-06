// Parses raw markdown (Karpathy/Obsidian-style wiki pages) into structured
// WikiDocuments. Deliberately dependency-free: a small YAML-ish frontmatter
// reader plus markdown heuristics, tuned for the "compiled wiki" the spec
// assumes (clear titles, status lines, summaries, cross-links).

import { RawWikiFile, WikiDocument, WikiLink } from "./types";

const FRONTMATTER_RE = /^---\s*\n([\s\S]*?)\n---\s*\n?/;
const MD_LINK_RE = /\[([^\]]+)\]\(([^)]+)\)/g;
const INLINE_TAG_RE = /(?:^|\s)#([a-zA-Z][\w/-]+)/g;
const WIKILINK_RE = /\[\[([^\]]+)\]\]/g;

/** Parse a tiny subset of YAML: `key: value` and inline/block lists. */
function parseFrontmatter(raw: string): Record<string, string | string[]> {
  const out: Record<string, string | string[]> = {};
  const lines = raw.split("\n");
  let currentListKey: string | null = null;

  for (const line of lines) {
    if (!line.trim()) continue;

    // Block list item: "  - value"
    const listItem = line.match(/^\s*-\s+(.+)$/);
    if (listItem && currentListKey) {
      const arr = (out[currentListKey] as string[]) || [];
      arr.push(stripQuotes(listItem[1].trim()));
      out[currentListKey] = arr;
      continue;
    }

    const kv = line.match(/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/);
    if (kv) {
      const key = kv[1].trim().toLowerCase();
      const value = kv[2].trim();
      if (value === "") {
        // Start of a block list.
        currentListKey = key;
        out[key] = [];
      } else if (value.startsWith("[") && value.endsWith("]")) {
        // Inline list: [a, b, c]
        out[key] = value
          .slice(1, -1)
          .split(",")
          .map((s) => stripQuotes(s.trim()))
          .filter(Boolean);
        currentListKey = null;
      } else {
        out[key] = stripQuotes(value);
        currentListKey = null;
      }
    }
  }
  return out;
}

function stripQuotes(s: string): string {
  return s.replace(/^["']|["']$/g, "");
}

function asArray(v: string | string[] | undefined): string[] {
  if (!v) return [];
  if (Array.isArray(v)) return v.filter(Boolean);
  return v
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Convert markdown body into roughly plain text for indexing. */
function toPlainText(md: string): string {
  return md
    .replace(MD_LINK_RE, "$1") // keep link text
    .replace(WIKILINK_RE, "$1")
    .replace(/[`*_>#~|]/g, " ")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/\r/g, "")
    .trim();
}

export function parseWikiFile(file: RawWikiFile): WikiDocument {
  let content = file.content.replace(/\r\n/g, "\n");
  let fm: Record<string, string | string[]> = {};

  const fmMatch = content.match(FRONTMATTER_RE);
  if (fmMatch) {
    fm = parseFrontmatter(fmMatch[1]);
    content = content.slice(fmMatch[0].length);
  }

  const lines = content.split("\n");

  // Title: frontmatter > first H1 > filename
  let title = (fm.title as string) || "";
  if (!title) {
    const h1 = lines.find((l) => /^#\s+/.test(l));
    if (h1) title = h1.replace(/^#\s+/, "").trim();
  }
  if (!title) title = file.name;

  // Headings
  const headings = lines
    .filter((l) => /^#{1,6}\s+/.test(l))
    .map((l) => l.replace(/^#{1,6}\s+/, "").trim());

  // Status / latest update / blocker — frontmatter or labelled lines in body.
  const status =
    (fm.status as string) || findLabelledLine(lines, ["status"]);
  const latestUpdate =
    (fm.latest_update as string) ||
    (fm["latest update"] as string) ||
    findLabelledLine(lines, ["latest update", "update", "latest"]);
  const blocker =
    (fm.blocker as string) ||
    findLabelledLine(lines, ["key blocker", "blocker", "blockers"]);

  // Summary: frontmatter > first non-heading, non-empty paragraph.
  let summary = (fm.summary as string) || (fm.description as string) || "";
  if (!summary) {
    for (const l of lines) {
      const t = l.trim();
      if (!t || /^#{1,6}\s+/.test(t) || /^[-*]\s/.test(t) || t.startsWith(">")) {
        continue;
      }
      summary = toPlainText(t);
      break;
    }
  }
  summary = summary.slice(0, 400);

  // Tags: frontmatter + inline #tags
  const tagSet = new Set<string>(asArray(fm.tags).map((t) => t.replace(/^#/, "")));
  let m: RegExpExecArray | null;
  INLINE_TAG_RE.lastIndex = 0;
  while ((m = INLINE_TAG_RE.exec(content)) !== null) tagSet.add(m[1]);

  // Aliases
  const aliases = asArray(fm.aliases || fm.alias);

  // Links: markdown links (prefer http/notion ones for quick-link buttons)
  const links: WikiLink[] = [];
  MD_LINK_RE.lastIndex = 0;
  while ((m = MD_LINK_RE.exec(content)) !== null) {
    const label = m[1].trim();
    const url = m[2].trim();
    if (/^https?:\/\//.test(url)) links.push({ label, url });
  }
  // Frontmatter explicit notion/url field
  for (const key of ["notion", "url", "link"]) {
    const v = fm[key];
    if (typeof v === "string" && /^https?:\/\//.test(v)) {
      links.unshift({ label: key === "notion" ? "Open Notion ↗" : "Open Link ↗", url: v });
    }
  }

  const body = toPlainText(content);

  return {
    id: file.path,
    title,
    summary,
    status: status || undefined,
    latestUpdate: latestUpdate || undefined,
    blocker: blocker || undefined,
    tags: [...tagSet],
    aliases,
    links: dedupeLinks(links),
    headings,
    body,
  };
}

function findLabelledLine(lines: string[], labels: string[]): string {
  for (const l of lines) {
    const cleaned = l.replace(/[*_>#`-]/g, "").trim();
    const idx = cleaned.indexOf(":");
    if (idx === -1) continue;
    const key = cleaned.slice(0, idx).trim().toLowerCase();
    if (labels.includes(key)) {
      const val = cleaned.slice(idx + 1).trim();
      if (val) return val;
    }
  }
  return "";
}

function dedupeLinks(links: WikiLink[]): WikiLink[] {
  const seen = new Set<string>();
  const out: WikiLink[] = [];
  for (const l of links) {
    if (seen.has(l.url)) continue;
    seen.add(l.url);
    out.push(l);
  }
  return out.slice(0, 4);
}
