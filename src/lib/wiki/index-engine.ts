// Builds a local TF-IDF search index over parsed wiki documents.
//
// Field weighting: titles/aliases/tags/headings carry more signal than body
// prose, so their tokens are repeated when accumulating term frequencies.
// The resulting per-document vectors are L2-normalised so matching reduces to
// a cosine similarity (spec §3.2).

import { WikiDocument, WikiIndex } from "./types";
import { tokenize } from "./tokenize";

const FIELD_WEIGHTS = {
  title: 5,
  aliases: 5,
  tags: 4,
  headings: 2,
  summary: 2,
  status: 2,
  latestUpdate: 2,
  body: 1,
} as const;

function weightedTokens(doc: WikiDocument): Record<string, number> {
  const tf: Record<string, number> = {};
  const add = (text: string | undefined, weight: number) => {
    if (!text) return;
    for (const tok of tokenize(text)) tf[tok] = (tf[tok] || 0) + weight;
  };

  add(doc.title, FIELD_WEIGHTS.title);
  for (const a of doc.aliases) add(a, FIELD_WEIGHTS.aliases);
  for (const t of doc.tags) add(t, FIELD_WEIGHTS.tags);
  for (const h of doc.headings) add(h, FIELD_WEIGHTS.headings);
  add(doc.summary, FIELD_WEIGHTS.summary);
  add(doc.status, FIELD_WEIGHTS.status);
  add(doc.latestUpdate, FIELD_WEIGHTS.latestUpdate);
  add(doc.body, FIELD_WEIGHTS.body);

  return tf;
}

/** Phrases that should resolve directly to a document (exact-entity matching). */
function entitiesFor(doc: WikiDocument): string[] {
  const phrases = new Set<string>();
  const push = (s: string) => {
    const norm = s.trim().toLowerCase();
    if (norm.length >= 3) phrases.add(norm);
  };
  push(doc.title);
  doc.aliases.forEach(push);
  doc.tags.forEach((t) => push(t.replace(/[-_/]/g, " ")));
  return [...phrases];
}

export function buildIndex(docs: WikiDocument[]): WikiIndex {
  const vectors: Record<string, Record<string, number>> = {};
  const df: Record<string, number> = {};
  const rawTf: Record<string, Record<string, number>> = {};
  const entityMap: Record<string, string[]> = {};

  for (const doc of docs) {
    const tf = weightedTokens(doc);
    rawTf[doc.id] = tf;
    for (const tok of Object.keys(tf)) df[tok] = (df[tok] || 0) + 1;

    for (const phrase of entitiesFor(doc)) {
      (entityMap[phrase] ||= []).push(doc.id);
    }
  }

  const n = Math.max(docs.length, 1);
  const idf: Record<string, number> = {};
  for (const tok of Object.keys(df)) {
    // Smoothed idf, always positive.
    idf[tok] = Math.log((n + 1) / (df[tok] + 1)) + 1;
  }

  // Build L2-normalised tf-idf vectors.
  for (const doc of docs) {
    const tf = rawTf[doc.id];
    const vec: Record<string, number> = {};
    let norm = 0;
    for (const [tok, freq] of Object.entries(tf)) {
      const w = (1 + Math.log(freq)) * (idf[tok] || 1);
      vec[tok] = w;
      norm += w * w;
    }
    norm = Math.sqrt(norm) || 1;
    for (const tok of Object.keys(vec)) vec[tok] /= norm;
    vectors[doc.id] = vec;
  }

  return {
    documents: docs,
    idf,
    vectors,
    entityMap,
    stats: {
      documentCount: docs.length,
      tokenCount: Object.keys(idf).length,
    },
  };
}
