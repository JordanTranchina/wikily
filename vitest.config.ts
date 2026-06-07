/// <reference types="vitest" />
import { defineConfig } from "vitest/config";
import path from "path";

// Standalone Vitest config so we don't pull in the Tauri-tailored dev server
// options from vite.config.ts. We only need the `@` alias to mirror tsconfig.
export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    // jsdom gives us `window`/`localStorage` for the storage-layer tests.
    environment: "jsdom",
    globals: true,
    setupFiles: ["src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    coverage: {
      provider: "v8",
      reporter: ["text", "text-summary", "html", "lcov"],
      include: ["src/lib/**/*.ts"],
      exclude: ["src/lib/**/*.{test,spec}.ts", "src/lib/**/index.ts"],
    },
  },
});
