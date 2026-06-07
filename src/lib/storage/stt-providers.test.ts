import { describe, it, expect, beforeEach } from "vitest";
import {
  getCustomSttProviders,
  addCustomSttProvider,
  updateCustomSttProvider,
  removeCustomSttProvider,
} from "./stt-providers";
import { STORAGE_KEYS } from "@/config";

// Speech-to-text provider management mirrors the AI provider workflow and backs
// the live transcription feature.

describe("custom STT providers CRUD", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("starts empty", () => {
    expect(getCustomSttProviders()).toEqual([]);
  });

  it("adds a provider flagged as custom", () => {
    const provider = addCustomSttProvider({ curl: "curl https://stt" });
    expect(provider).not.toBeNull();
    expect(provider!.isCustom).toBe(true);
    expect(getCustomSttProviders()).toHaveLength(1);
  });

  it("updates an existing provider", () => {
    const provider = addCustomSttProvider({ curl: "curl old" })!;
    expect(updateCustomSttProvider(provider.id!, { curl: "curl new" })).toBe(
      true
    );
    expect(getCustomSttProviders()[0].curl).toBe("curl new");
  });

  it("returns false updating an unknown provider", () => {
    expect(updateCustomSttProvider("nope", { curl: "x" })).toBe(false);
  });

  it("removes a provider", () => {
    const provider = addCustomSttProvider({ curl: "curl x" })!;
    expect(removeCustomSttProvider(provider.id!)).toBe(true);
    expect(getCustomSttProviders()).toEqual([]);
  });

  it("returns false removing an unknown provider", () => {
    expect(removeCustomSttProvider("nope")).toBe(false);
  });

  it("survives corrupt storage", () => {
    localStorage.setItem(STORAGE_KEYS.CUSTOM_SPEECH_PROVIDERS, "garbage");
    expect(getCustomSttProviders()).toEqual([]);
  });

  it("filters entries lacking id/isCustom", () => {
    localStorage.setItem(
      STORAGE_KEYS.CUSTOM_SPEECH_PROVIDERS,
      JSON.stringify([
        { id: "1", isCustom: true, curl: "ok" },
        { curl: "no id/flag" },
      ])
    );
    expect(getCustomSttProviders()).toHaveLength(1);
  });
});
