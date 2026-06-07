// Vitest global setup.
//
// Node 22+/25 ship a native `globalThis.localStorage` (Web Storage) that, when
// run without a backing file, is only partially implemented and shadows the one
// jsdom installs — `clear()` is missing and reads/writes don't persist. The app
// itself runs in a real Tauri WebView where localStorage works normally, so this
// is purely a test-runtime quirk. We replace the global with a clean, spec-
// compliant in-memory implementation so storage-layer tests are deterministic.

class MemoryStorage implements Storage {
  private store = new Map<string, string>();

  get length(): number {
    return this.store.size;
  }

  clear(): void {
    this.store.clear();
  }

  getItem(key: string): string | null {
    return this.store.has(key) ? this.store.get(key)! : null;
  }

  key(index: number): string | null {
    return Array.from(this.store.keys())[index] ?? null;
  }

  removeItem(key: string): void {
    this.store.delete(key);
  }

  setItem(key: string, value: string): void {
    this.store.set(key, String(value));
  }
}

Object.defineProperty(globalThis, "localStorage", {
  value: new MemoryStorage(),
  writable: true,
  configurable: true,
});
