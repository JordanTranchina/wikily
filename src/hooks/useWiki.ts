import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  buildIndex,
  matchTranscript,
  parseWikiFile,
  RawWikiFile,
  WikiIndex,
  WikiMatch,
} from "@/lib/wiki";
import {
  DEFAULT_WIKI_CONFIDENCE_THRESHOLD,
  STORAGE_KEYS,
} from "@/config";
import { safeLocalStorage } from "@/lib";

interface ScanResult {
  files: RawWikiFile[];
  scanned_dirs: number;
}

export interface WikiIndexStats {
  documentCount: number;
  tokenCount: number;
  scannedDirs: number;
  indexTimeMs: number;
}

export type UseWikiType = ReturnType<typeof useWiki>;

/**
 * Owns the local wiki: directory path, the in-memory TF-IDF index, and the
 * confidence threshold. Scanning + parsing + indexing all happen on-device.
 */
export function useWiki() {
  const [directory, setDirectoryState] = useState<string>(
    () => safeLocalStorage.getItem(STORAGE_KEYS.WIKI_DIRECTORY) || ""
  );
  const [threshold, setThresholdState] = useState<number>(() => {
    const saved = safeLocalStorage.getItem(
      STORAGE_KEYS.WIKI_CONFIDENCE_THRESHOLD
    );
    const n = saved ? parseFloat(saved) : NaN;
    return Number.isFinite(n) ? n : DEFAULT_WIKI_CONFIDENCE_THRESHOLD;
  });
  const [isIndexing, setIsIndexing] = useState(false);
  const [stats, setStats] = useState<WikiIndexStats | null>(null);
  const [error, setError] = useState<string>("");

  const indexRef = useRef<WikiIndex | null>(null);

  const scanAndIndex = useCallback(
    async (dir?: string) => {
      const target = (dir ?? directory).trim();
      if (!target) {
        setError("No wiki directory configured.");
        return null;
      }
      setIsIndexing(true);
      setError("");
      try {
        const started = performance.now();
        const result = await invoke<ScanResult>("scan_wiki_directory", {
          path: target,
        });
        const docs = result.files.map(parseWikiFile);
        const index = buildIndex(docs);
        indexRef.current = index;
        const indexTimeMs = Math.round(performance.now() - started);
        const nextStats: WikiIndexStats = {
          documentCount: index.stats.documentCount,
          tokenCount: index.stats.tokenCount,
          scannedDirs: result.scanned_dirs,
          indexTimeMs,
        };
        setStats(nextStats);
        if (docs.length === 0) {
          setError("No markdown files found in that directory.");
        }
        return nextStats;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        setError(msg);
        indexRef.current = null;
        setStats(null);
        return null;
      } finally {
        setIsIndexing(false);
      }
    },
    [directory]
  );

  const setDirectory = useCallback((dir: string) => {
    setDirectoryState(dir);
    safeLocalStorage.setItem(STORAGE_KEYS.WIKI_DIRECTORY, dir);
  }, []);

  const setThreshold = useCallback((value: number) => {
    const clamped = Math.min(1, Math.max(0, value));
    setThresholdState(clamped);
    safeLocalStorage.setItem(
      STORAGE_KEYS.WIKI_CONFIDENCE_THRESHOLD,
      String(clamped)
    );
  }, []);

  /** Run a raw search and return ranked matches (no threshold applied). */
  const search = useCallback((transcript: string): WikiMatch[] => {
    if (!indexRef.current) return [];
    return matchTranscript(indexRef.current, transcript, { topK: 3 });
  }, []);

  /** Return the single best match only if it clears the confidence threshold. */
  const match = useCallback(
    (transcript: string): WikiMatch | null => {
      const results = search(transcript);
      const top = results[0];
      if (top && top.score >= threshold) return top;
      return null;
    },
    [search, threshold]
  );

  const isReady = useCallback(() => indexRef.current !== null, []);

  // Auto-index on mount if a directory is already configured.
  useEffect(() => {
    if (directory.trim()) {
      scanAndIndex(directory);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return {
    directory,
    setDirectory,
    threshold,
    setThreshold,
    isIndexing,
    stats,
    error,
    scanAndIndex,
    search,
    match,
    isReady,
  };
}
