// Small, stable, dependency-free string hash (FNV-1a, 32-bit).
//
// Used to fingerprint the transcript window for local-only match telemetry
// (Tech Spec §7 KPI) so we log *that* a topic recurred without ever storing the
// raw transcript text (§9). Not cryptographic — collision-resistance is not a
// requirement here, only stability and cheapness.
export function stableHash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    // 32-bit FNV prime multiply, kept in the unsigned 32-bit range.
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}
