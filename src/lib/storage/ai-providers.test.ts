import { describe, it, expect, beforeEach } from "vitest";
import {
  getCustomAiProviders,
  setCustomAiProviders,
  addCustomAiProvider,
  updateCustomAiProvider,
  removeCustomAiProvider,
} from "./ai-providers";
import { STORAGE_KEYS } from "@/config";

// Managing custom AI providers is a primary settings workflow. These functions
// persist to localStorage and must survive corrupt/legacy data without throwing.

describe("custom AI providers CRUD", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("returns an empty array when nothing is stored", () => {
    expect(getCustomAiProviders()).toEqual([]);
  });

  it("adds a provider with a generated id and isCustom flag", () => {
    const provider = addCustomAiProvider({ curl: "curl https://api" });
    expect(provider).not.toBeNull();
    expect(provider!.id).toBeTruthy();
    expect(provider!.isCustom).toBe(true);
    expect(getCustomAiProviders()).toHaveLength(1);
  });

  it("persists added providers across reads", () => {
    addCustomAiProvider({ curl: "curl a" });
    addCustomAiProvider({ curl: "curl b" });
    const stored = getCustomAiProviders();
    expect(stored.map((p) => p.curl)).toEqual(["curl a", "curl b"]);
  });

  it("updates an existing provider and returns true", () => {
    const provider = addCustomAiProvider({ curl: "curl old" })!;
    const ok = updateCustomAiProvider(provider.id!, { curl: "curl new" });
    expect(ok).toBe(true);
    expect(getCustomAiProviders()[0].curl).toBe("curl new");
  });

  it("returns false when updating a non-existent provider", () => {
    expect(updateCustomAiProvider("does-not-exist", { curl: "x" })).toBe(false);
  });

  it("removes a provider and returns true", () => {
    const provider = addCustomAiProvider({ curl: "curl x" })!;
    expect(removeCustomAiProvider(provider.id!)).toBe(true);
    expect(getCustomAiProviders()).toEqual([]);
  });

  it("returns false when removing a non-existent provider", () => {
    addCustomAiProvider({ curl: "curl x" });
    expect(removeCustomAiProvider("nope")).toBe(false);
    expect(getCustomAiProviders()).toHaveLength(1);
  });

  it("ignores corrupt JSON in storage and returns an empty array", () => {
    localStorage.setItem(STORAGE_KEYS.CUSTOM_AI_PROVIDERS, "{not json");
    expect(getCustomAiProviders()).toEqual([]);
  });

  it("filters out entries missing required shape (id/isCustom/curl)", () => {
    setCustomAiProviders([
      { id: "1", isCustom: true, curl: "curl ok" },
      { isCustom: true, curl: "no id" } as any,
      { id: "2", isCustom: false, curl: "not custom" } as any,
      { id: "3", isCustom: true } as any, // missing curl string
    ]);
    const result = getCustomAiProviders();
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("1");
  });

  it("returns an empty array when stored value is not an array", () => {
    localStorage.setItem(
      STORAGE_KEYS.CUSTOM_AI_PROVIDERS,
      JSON.stringify({ foo: "bar" })
    );
    expect(getCustomAiProviders()).toEqual([]);
  });
});
