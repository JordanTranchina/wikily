import { useState } from "react";
import {
  Header,
  Input,
  Button,
  Textarea,
  Slider,
  Badge,
} from "@/components";
import { PageLayout } from "@/layouts";
import { useWiki } from "@/hooks";
import { WikiMatch } from "@/lib/wiki";
import {
  FolderSearchIcon,
  LoaderIcon,
  RefreshCwIcon,
  SearchIcon,
  CheckCircle2Icon,
  AlertCircleIcon,
} from "lucide-react";

/**
 * Wikily settings: point the app at a local "LLM Wiki" directory, index it
 * on-device, tune the proactive-trigger confidence, and test transcript
 * matching without needing a live call (spec §3.2 / Milestones 3 & 4).
 */
const Wiki = () => {
  const {
    directory,
    setDirectory,
    threshold,
    setThreshold,
    isIndexing,
    stats,
    error,
    scanAndIndex,
    search,
  } = useWiki();

  const [pathDraft, setPathDraft] = useState(directory);
  const [testTranscript, setTestTranscript] = useState(
    "How are you progressing with the Becky promotion?"
  );
  const [testResults, setTestResults] = useState<WikiMatch[] | null>(null);

  const handleIndex = async () => {
    setDirectory(pathDraft.trim());
    await scanAndIndex(pathDraft.trim());
    setTestResults(null);
  };

  const handleTest = () => {
    setTestResults(search(testTranscript));
  };

  return (
    <PageLayout
      title="Wiki Engine"
      description="Connect a local markdown wiki and tune proactive matching"
    >
      {/* Directory configuration */}
      <div className="space-y-2">
        <Header
          title="Wiki Directory"
          description="Point Wikily at a local folder of markdown files (Obsidian / Karpathy-style vault). Everything is parsed and indexed on-device."
          isMainTitle
        />
        <div className="flex items-center gap-2">
          <Input
            value={pathDraft}
            onChange={(e) => setPathDraft(e.target.value)}
            placeholder="/Users/you/Documents/MyKnowledgeWiki"
            className="flex-1"
          />
          <Button
            onClick={handleIndex}
            disabled={isIndexing || !pathDraft.trim()}
            className="gap-1.5"
          >
            {isIndexing ? (
              <LoaderIcon className="h-4 w-4 animate-spin" />
            ) : stats ? (
              <RefreshCwIcon className="h-4 w-4" />
            ) : (
              <FolderSearchIcon className="h-4 w-4" />
            )}
            {isIndexing ? "Indexing…" : stats ? "Re-index" : "Scan & Index"}
          </Button>
        </div>

        {error && (
          <div className="flex items-center gap-2 text-xs text-red-600">
            <AlertCircleIcon className="h-3.5 w-3.5" />
            {error}
          </div>
        )}

        {stats && !error && (
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <CheckCircle2Icon className="h-3.5 w-3.5 text-green-500" />
            Indexed <strong>{stats.documentCount}</strong> pages (
            {stats.tokenCount} terms) across {stats.scannedDirs} folders in{" "}
            {stats.indexTimeMs}ms.
          </div>
        )}
      </div>

      {/* Confidence threshold */}
      <div className="space-y-3">
        <Header
          title="Proactive Confidence Threshold"
          description="A wiki card only fades in over your call when match confidence clears this bar. Lower = more eager, higher = fewer interruptions."
          isMainTitle
        />
        <div className="flex items-center gap-4">
          <Slider
            min={0}
            max={100}
            step={1}
            value={[Math.round(threshold * 100)]}
            onValueChange={(v) => setThreshold((v[0] ?? 0) / 100)}
            className="max-w-md"
          />
          <Badge variant="secondary" className="tabular-nums">
            {Math.round(threshold * 100)}%
          </Badge>
        </div>
      </div>

      {/* Test panel */}
      <div className="space-y-3">
        <Header
          title="Test a Transcript"
          description="Paste what a client might say. Wikily runs the same offline match it uses live and shows which pages it would surface."
          isMainTitle
        />
        <Textarea
          value={testTranscript}
          onChange={(e) => setTestTranscript(e.target.value)}
          placeholder="e.g. We're having trouble with the OAuth redirect URI for our sandbox…"
          className="min-h-20"
        />
        <Button
          onClick={handleTest}
          disabled={!stats || isIndexing}
          variant="outline"
          className="gap-1.5"
        >
          <SearchIcon className="h-4 w-4" />
          Find Match
        </Button>

        {testResults && (
          <div className="space-y-2 pt-1">
            {testResults.length === 0 ? (
              <p className="text-xs text-muted-foreground">
                No matching pages found.
              </p>
            ) : (
              testResults.map((m) => {
                const wouldTrigger = m.score >= threshold;
                return (
                  <div
                    key={m.document.id}
                    className={`rounded-lg border p-3 space-y-1 ${
                      wouldTrigger
                        ? "border-green-500/40 bg-green-500/5"
                        : "border-border/50"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-medium truncate">
                        {m.document.title}
                      </span>
                      <Badge
                        variant={wouldTrigger ? "default" : "secondary"}
                        className="tabular-nums flex-shrink-0"
                      >
                        {Math.round(m.score * 100)}%
                      </Badge>
                    </div>
                    {m.document.status && (
                      <p className="text-xs text-muted-foreground">
                        Status: {m.document.status}
                      </p>
                    )}
                    <p className="text-xs text-foreground/80 line-clamp-2">
                      {m.document.latestUpdate || m.document.summary}
                    </p>
                    {m.matchedEntities.length > 0 && (
                      <p className="text-[10px] text-muted-foreground">
                        Matched: {m.matchedEntities.join(", ")}
                      </p>
                    )}
                    {wouldTrigger && (
                      <p className="text-[10px] font-medium text-green-600">
                        ✓ Would trigger a proactive card
                      </p>
                    )}
                  </div>
                );
              })
            )}
          </div>
        )}
      </div>
    </PageLayout>
  );
};

export default Wiki;
