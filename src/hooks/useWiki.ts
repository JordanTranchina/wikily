import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  buildIndex,
  matchTranscript,
  parseWikiFile,
  RawWikiFile,
  WikiDocument,
  WikiIndex,
  WikiMatch,
} from "@/lib/wiki";
import {
  DEFAULT_WIKI_CONFIDENCE_THRESHOLD,
  DEFAULT_WIKI_MATCH_LOG_ENABLED,
  DEFAULT_WIKI_SUMMARY_MODE,
  DEFAULT_WIKI_TRANSCRIPTION_MODE,
  STORAGE_KEYS,
  WikiSummaryMode,
  WikiTranscriptionMode,
} from "@/config";
import { safeLocalStorage, loadWikiCache, persistWikiCache } from "@/lib";

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
  const [transcriptionMode, setTranscriptionModeState] =
    useState<WikiTranscriptionMode>(
      () =>
        (safeLocalStorage.getItem(
          STORAGE_KEYS.WIKI_TRANSCRIPTION_MODE
        ) as WikiTranscriptionMode) || DEFAULT_WIKI_TRANSCRIPTION_MODE
    );
  const [summaryMode, setSummaryModeState] = useState<WikiSummaryMode>(
    () =>
      (safeLocalStorage.getItem(
        STORAGE_KEYS.WIKI_SUMMARY_MODE
      ) as WikiSummaryMode) || DEFAULT_WIKI_SUMMARY_MODE
  );
  const [matchLogEnabled, setMatchLogEnabledState] = useState<boolean>(() => {
    const saved = safeLocalStorage.getItem(STORAGE_KEYS.WIKI_MATCH_LOG_ENABLED);
    return saved === null ? DEFAULT_WIKI_MATCH_LOG_ENABLED : saved === "true";
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

        // Incremental parse: reuse cached parsed docs for files whose content
        // hash is unchanged since the last index; only (re)parse changed/new
        // files (spec §5.7). Falls back to a full parse if the cache is empty.
        const cache = await loadWikiCache();
        const persistEntries: { hash: string; doc: WikiDocument }[] = [];
        const docs: WikiDocument[] = result.files.map((file) => {
          const cached = file.hash ? cache.get(file.path) : undefined;
          const doc =
            cached && cached.hash === file.hash
              ? cached.doc
              : parseWikiFile(file);
          persistEntries.push({ hash: file.hash ?? "", doc });
          return doc;
        });

        const index = buildIndex(docs);
        indexRef.current = index;

        // Persist the fresh cache (best-effort; matching works in-memory too).
        void persistWikiCache(persistEntries);
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

  const setTranscriptionMode = useCallback((mode: WikiTranscriptionMode) => {
    setTranscriptionModeState(mode);
    safeLocalStorage.setItem(STORAGE_KEYS.WIKI_TRANSCRIPTION_MODE, mode);
  }, []);

  const setSummaryMode = useCallback((mode: WikiSummaryMode) => {
    setSummaryModeState(mode);
    safeLocalStorage.setItem(STORAGE_KEYS.WIKI_SUMMARY_MODE, mode);
  }, []);

  const setMatchLogEnabled = useCallback((enabled: boolean) => {
    setMatchLogEnabledState(enabled);
    safeLocalStorage.setItem(
      STORAGE_KEYS.WIKI_MATCH_LOG_ENABLED,
      String(enabled)
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
    transcriptionMode,
    setTranscriptionMode,
    summaryMode,
    setSummaryMode,
    matchLogEnabled,
    setMatchLogEnabled,
    isIndexing,
    stats,
    error,
    scanAndIndex,
    search,
    match,
    isReady,
  };
}
