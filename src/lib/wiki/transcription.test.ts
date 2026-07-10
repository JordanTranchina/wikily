import { describe, it, expect } from "vitest";
import { planLocalFallback, LOCAL_UNAVAILABLE_SENTINEL } from "./transcription";

describe("planLocalFallback (Tech Spec §6 local-first policy)", () => {
  const unavailable = `${LOCAL_UNAVAILABLE_SENTINEL}: whisper.cpp model not found`;

  it("falls back to cloud when local is unavailable and cloud is configured", () => {
    expect(planLocalFallback(unavailable, true)).toEqual({ fallback: "cloud" });
  });

  it("stops and prompts setup when local is unavailable and no cloud is configured", () => {
    const decision = planLocalFallback(unavailable, false);
    expect(decision.fallback).toBe("none");
    if (decision.fallback === "none") {
      expect(decision.reason).toMatch(/isn't set up/i);
    }
  });

  it("surfaces a real local error instead of silently falling back to cloud", () => {
    const real = "whisper.cpp failed: corrupt audio";
    // Even with cloud available, a genuine (non-sentinel) error must not be
    // masked by a cloud fallback — it should propagate.
    const decision = planLocalFallback(real, true);
    expect(decision).toEqual({ fallback: "none", reason: real });
  });
});
