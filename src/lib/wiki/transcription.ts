// Transcription fallback policy (Tech Spec §6).
//
// Wikily is local-first: on-device whisper.cpp is the default source. When the
// local model/sidecar isn't installed, `transcribe_local` returns an error
// beginning with LOCAL_TRANSCRIPTION_UNAVAILABLE. This pure helper decides what
// to do next so the rule is unit-testable in isolation from the Tauri/audio
// plumbing in useSystemAudio.

/** Sentinel the Rust `transcribe_local` command uses for a missing model/sidecar. */
export const LOCAL_UNAVAILABLE_SENTINEL = "LOCAL_TRANSCRIPTION_UNAVAILABLE";

export type LocalFallbackDecision =
  | { fallback: "cloud" }
  | { fallback: "none"; reason: string };

/**
 * Given the error thrown by a local transcription attempt, decide whether to
 * fall back to cloud STT.
 *
 * - Local unavailable + cloud configured  → fall back to cloud (opt-in per §6).
 * - Local unavailable + no cloud           → stop and prompt the user to finish
 *                                            local setup (audio stays on-device).
 * - Any other (real) local error           → surface it; don't silently fall back.
 */
export function planLocalFallback(
  errorMessage: string,
  cloudAvailable: boolean
): LocalFallbackDecision {
  const unavailable = errorMessage.includes(LOCAL_UNAVAILABLE_SENTINEL);
  if (unavailable) {
    if (cloudAvailable) return { fallback: "cloud" };
    return {
      fallback: "none",
      reason:
        "On-device transcription isn't set up yet. Enable a cloud speech provider in Settings, or finish local whisper.cpp setup.",
    };
  }
  return { fallback: "none", reason: errorMessage };
}
