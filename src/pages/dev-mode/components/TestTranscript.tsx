import { useState } from "react";
import { Header, Textarea, Button, Badge } from "@/components";
import { useWiki } from "@/hooks";
import { WikiMatch } from "@/lib/wiki";
import { SearchIcon } from "lucide-react";

export const TestTranscript = () => {
  const { threshold, stats, isIndexing, search } = useWiki();

  const [testTranscript, setTestTranscript] = useState(
    "How are you progressing with the Becky promotion?"
  );
  const [testResults, setTestResults] = useState<WikiMatch[] | null>(null);

  const handleTest = () => {
    setTestResults(search(testTranscript));
  };

  return (
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
  );
};
