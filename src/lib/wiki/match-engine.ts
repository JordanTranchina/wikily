// Matches a live transcript window against the local wiki index.
//
// Two signals are combined (spec §3.2):
//   1. Cosine similarity between the transcript's tf-idf vector and each
//      document vector (semantic-ish lexical overlap).
//   2. Exact entity hits — when a document's title/alias/tag phrase appears
//      verbatim in the transcript (e.g. "Becky promotion"), which is the
//      strongest signal a rep is talking about that page.

import { WikiIndex, WikiMatch } from "./types";
import { tokenize, termFrequencies } from "./tokenize";

export interface MatchOptions {
  /** Max number of matches to return. */
  topK?: number;
  /** Per-exact-entity-hit additive boost. */
  entityBoost?: number;
}

/** Normalise text for phrase/substring entity matching. */
function normalisePhrase(text: string): string {
  return ` ${text.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()} `;
}

/** Build an L2-normalised tf-idf query vector from the transcript window. */
function queryVector(
  index: WikiIndex,
  tokens: string[]
): Record<string, number> {
  const tf = termFrequencies(tokens);
  const vec: Record<string, number> = {};
  let norm = 0;
  for (const [tok, freq] of Object.entries(tf)) {
    const idf = index.idf[tok];
    if (!idf) continue; // term not in any document — ignore
    const w = (1 + Math.log(freq)) * idf;
    vec[tok] = w;
    norm += w * w;
  }
  norm = Math.sqrt(norm) || 1;
  for (const tok of Object.keys(vec)) vec[tok] /= norm;
  return vec;
}

function cosine(
  a: Record<string, number>,
  b: Record<string, number>
): number {
  // Both vectors are already L2-normalised → dot product is the cosine.
  let dot = 0;
  // Iterate over the smaller vector.
  const [small, large] = Object.keys(a).length < Object.keys(b).length
    ? [a, b]
    : [b, a];
  for (const [tok, w] of Object.entries(small)) {
    const w2 = large[tok];
    if (w2) dot += w * w2;
  }
  return dot;
}

export function matchTranscript(
  index: WikiIndex,
  transcript: string,
  options: MatchOptions = {}
): WikiMatch[] {
  const { topK = 3, entityBoost = 0.4 } = options;
  if (!transcript.trim() || index.documents.length === 0) return [];

  const qTokens = tokenize(transcript);
  const qVec = queryVector(index, qTokens);
  const normTranscript = normalisePhrase(transcript);

  // Exact entity hits → doc id -> matched phrases.
  const entityHits: Record<string, Set<string>> = {};
  for (const [phrase, docIds] of Object.entries(index.entityMap)) {
    const needle = normalisePhrase(phrase);
    if (needle.length > 4 && normTranscript.includes(needle)) {
      for (const id of docIds) {
        (entityHits[id] ||= new Set()).add(phrase);
      }
    }
  }

  const matches: WikiMatch[] = [];
  for (const doc of index.documents) {
    const sim = cosine(qVec, index.vectors[doc.id] || {});
    const hits = entityHits[doc.id];
    const boost = hits ? entityBoost + (hits.size - 1) * 0.15 : 0;
    const score = Math.min(1, sim + boost);
    if (score <= 0) continue;
    matches.push({
      document: doc,
      score,
      matchedEntities: hits ? [...hits] : [],
    });
  }

  matches.sort((a, b) => b.score - a.score);
  return matches.slice(0, topK);
}
