import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { safeLocalStorage } from "./helper";

// safeLocalStorage wraps every persistence call in the app. It must never throw,
// even if the browser blocks storage (private mode, quota exceeded), otherwise a
// failed write would crash unrelated UI.

describe("safeLocalStorage", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("round-trips a value", () => {
    safeLocalStorage.setItem("k", "v");
    expect(safeLocalStorage.getItem("k")).toBe("v");
  });

  it("returns null for a missing key", () => {
    expect(safeLocalStorage.getItem("missing")).toBeNull();
  });

  it("removes a value", () => {
    safeLocalStorage.setItem("k", "v");
    safeLocalStorage.removeItem("k");
    expect(safeLocalStorage.getItem("k")).toBeNull();
  });

  describe("when localStorage throws", () => {
    afterEach(() => {
      vi.restoreAllMocks();
    });

    it("getItem swallows the error and returns null", () => {
      vi.spyOn(globalThis.localStorage, "getItem").mockImplementation(() => {
        throw new Error("blocked");
      });
      expect(safeLocalStorage.getItem("k")).toBeNull();
    });

    it("setItem swallows quota errors", () => {
      vi.spyOn(globalThis.localStorage, "setItem").mockImplementation(() => {
        throw new Error("QuotaExceeded");
      });
      expect(() => safeLocalStorage.setItem("k", "v")).not.toThrow();
    });

    it("removeItem swallows errors", () => {
      vi.spyOn(globalThis.localStorage, "removeItem").mockImplementation(() => {
        throw new Error("blocked");
      });
      expect(() => safeLocalStorage.removeItem("k")).not.toThrow();
    });
  });
});
