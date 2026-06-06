// Lightweight tokenizer for the local matching engine.
// English stopword removal + simple normalisation. No external deps.

const STOPWORDS = new Set([
  "a", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by",
  "can", "could", "did", "do", "does", "doing", "for", "from", "had", "has",
  "have", "having", "he", "her", "here", "hers", "him", "his", "how", "i",
  "if", "in", "into", "is", "it", "its", "just", "me", "my", "no", "not",
  "of", "on", "or", "our", "out", "over", "she", "so", "some", "than", "that",
  "the", "their", "them", "then", "there", "these", "they", "this", "to",
  "too", "up", "us", "very", "was", "we", "were", "what", "when", "where",
  "which", "while", "who", "why", "will", "with", "would", "you", "your",
  // conversational filler common in live transcripts
  "um", "uh", "okay", "ok", "yeah", "hey", "hi", "hello", "thanks", "thank",
  "like", "know", "going", "get", "got", "want", "need", "lets", "let",
]);

/** Split text into normalised, stopword-filtered tokens. */
export function tokenize(text: string): string[] {
  if (!text) return [];
  return text
    .toLowerCase()
    .replace(/[`*_>#~|\[\]()]/g, " ")
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length >= 2 && !STOPWORDS.has(t) && !/^\d+$/.test(t));
}

/** Count term frequencies for a token list. */
export function termFrequencies(tokens: string[]): Record<string, number> {
  const tf: Record<string, number> = {};
  for (const t of tokens) tf[t] = (tf[t] || 0) + 1;
  return tf;
}
