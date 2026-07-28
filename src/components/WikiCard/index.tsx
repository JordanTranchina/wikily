import { useState } from "react";
import { Button, Badge, Input } from "@/components";
import { useCopyToClipboard } from "@/hooks";
import { ChatConversation } from "@/hooks";
import { WikiMatch } from "@/lib/wiki";
import { openUrl, openPath } from "@tauri-apps/plugin-opener";
import {
  LightbulbIcon,
  CopyIcon,
  CheckIcon,
  ExternalLinkIcon,
  FileTextIcon,
  XIcon,
  ChevronDownIcon,
  ChevronUpIcon,
  SearchIcon,
  SendIcon,
  FileSearchIcon,
} from "lucide-react";

interface WikiCardProps {
  match: WikiMatch;
  onDismiss: () => void;
  /** Called when the rep copies or opens the card — engagement KPI (spec §7). */
  onEngage?: () => void;
  /** Saved quick-action prompts (e.g. "What should I say?", "Follow-up questions"). */
  quickActions?: string[];
  /** Runs a prompt through the AI with the live call as context. */
  onQuickAction?: (action: string) => void;
  /** The live Q&A thread for this call, newest message first. */
  conversation?: ChatConversation;
  isAIProcessing?: boolean;
  /** Runs an on-device search over the wiki index (no threshold applied). */
  onSearch?: (query: string) => WikiMatch[];
  /** The most recent transcribed utterance — the default query subject. */
  lastTranscription?: string;
}

/**
 * Proactive Wikily HUD card (spec §3.3). Fades in over the active call when a
 * live transcript matches a local wiki page above the confidence threshold,
 * and doubles as the persistent Q&A panel for the call (quick actions, a
 * running thread, and on-device wiki search) — see design screen "Live
 * overlay during a Zoom call".
 */
export const WikiCard = ({
  match,
  onDismiss,
  onEngage,
  quickActions = [],
  onQuickAction,
  conversation,
  isAIProcessing,
  onSearch,
  lastTranscription,
}: WikiCardProps) => {
  const { document: doc, score } = match;
  const [collapsed, setCollapsed] = useState(false);
  const [askDraft, setAskDraft] = useState("");
  const [queryResults, setQueryResults] = useState<WikiMatch[] | null>(null);
  const [querySubject, setQuerySubject] = useState("");

  // Build a copy-friendly status blob.
  const copyText = [
    doc.title,
    doc.status ? `Status: ${doc.status}` : "",
    doc.latestUpdate ? `Latest: ${doc.latestUpdate}` : "",
    doc.blocker ? `Blocker: ${doc.blocker}` : "",
  ]
    .filter(Boolean)
    .join("\n");

  const { isCopied, handleCopy } = useCopyToClipboard({ text: copyText });

  const handleCopyAndTrack = () => {
    onEngage?.();
    handleCopy();
  };

  const openLocalFile = async (path: string = doc.id) => {
    onEngage?.();
    try {
      await openPath(path);
    } catch (err) {
      console.error("Failed to open wiki file:", err);
    }
  };

  const openLink = (url: string) => {
    onEngage?.();
    openUrl(url);
  };

  const runAction = (action: string) => {
    if (!action.trim() || !onQuickAction) return;
    onEngage?.();
    onQuickAction(action.trim());
  };

  const runQuery = () => {
    const subject = lastTranscription?.trim() || doc.title;
    if (!onSearch || !subject) return;
    onEngage?.();
    setQuerySubject(subject);
    setQueryResults(onSearch(subject));
  };

  const submitAsk = () => {
    if (!askDraft.trim()) return;
    runAction(askDraft);
    setAskDraft("");
  };

  // Most recent exchange only — messages are stored newest-first.
  const thread = (conversation?.messages ?? []).slice(0, 4).reverse();

  if (collapsed) {
    return (
      <div className="absolute right-2 top-14 z-50 animate-in fade-in slide-in-from-top-1 duration-200">
        <div className="flex items-center gap-2 rounded-full border border-border/60 bg-card/95 backdrop-blur-md shadow-lg px-3 py-1.5">
          <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground flex-none">
            W
          </div>
          <span
            className="text-xs font-medium max-w-[10rem] truncate"
            title={doc.title}
          >
            {doc.title}
          </span>
          <button
            type="button"
            className="text-muted-foreground hover:text-foreground"
            title="Show"
            onClick={() => setCollapsed(false)}
          >
            <ChevronDownIcon className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="absolute right-2 top-14 z-50 w-80 animate-in fade-in slide-in-from-top-2 duration-300">
      <div className="rounded-xl border border-secondary/40 bg-card/95 backdrop-blur-md shadow-lg overflow-hidden">
        {/* Header */}
        <div className="flex items-start justify-between gap-2 px-3 pt-3">
          <div className="flex items-center gap-1.5 min-w-0">
            <LightbulbIcon className="h-4 w-4 text-amber-500 flex-shrink-0" />
            <span className="text-xs font-semibold truncate" title={doc.title}>
              {doc.title}
            </span>
          </div>
          <div className="flex items-center gap-1 flex-shrink-0">
            <Badge
              variant="secondary"
              className="text-[9px] px-1.5 py-0 h-4"
              title="Match confidence"
            >
              {Math.round(score * 100)}%
            </Badge>
            <Button
              size="icon"
              variant="ghost"
              className="h-5 w-5"
              title="Hide"
              onClick={() => setCollapsed(true)}
            >
              <ChevronUpIcon className="h-3 w-3" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              className="h-5 w-5"
              title="Dismiss"
              onClick={onDismiss}
            >
              <XIcon className="h-3 w-3" />
            </Button>
          </div>
        </div>

        <div className="px-3 pb-3 pt-2 space-y-2">
          {/* Status */}
          {doc.status && (
            <div className="flex items-center gap-1.5">
              <span className="text-[10px] text-muted-foreground">Status:</span>
              <Badge className="text-[9px] px-1.5 py-0 h-4">{doc.status}</Badge>
            </div>
          )}

          {/* Latest update / summary */}
          <p className="text-[11px] leading-snug text-foreground/90">
            {doc.latestUpdate || doc.summary}
          </p>

          {/* Blocker */}
          {doc.blocker && (
            <p className="text-[10px] leading-snug text-muted-foreground">
              <span className="font-medium">Blocker:</span> {doc.blocker}
            </p>
          )}

          {/* Actions */}
          <div className="flex flex-wrap items-center gap-1.5">
            <Button
              size="sm"
              variant="outline"
              className="h-6 text-[10px] gap-1 px-2"
              onClick={handleCopyAndTrack}
              title="Copy status to clipboard"
            >
              {isCopied ? (
                <CheckIcon className="h-3 w-3 text-green-500" />
              ) : (
                <CopyIcon className="h-3 w-3" />
              )}
              {isCopied ? "Copied" : "Copy Status"}
            </Button>

            <Button
              size="sm"
              variant="outline"
              className="h-6 text-[10px] gap-1 px-2"
              onClick={() => openLocalFile()}
              title="Open the local wiki file"
            >
              <FileTextIcon className="h-3 w-3" />
              Open Page
            </Button>

            {doc.links.slice(0, 2).map((link) => (
              <Button
                key={link.url}
                size="sm"
                variant="outline"
                className="h-6 text-[10px] gap-1 px-2"
                onClick={() => openLink(link.url)}
                title={link.url}
              >
                <ExternalLinkIcon className="h-3 w-3" />
                {link.label.length > 18
                  ? link.label.slice(0, 18) + "…"
                  : link.label}
              </Button>
            ))}
          </div>

          {/* Persistent Q&A thread for this call */}
          {thread.length > 0 && (
            <div className="space-y-1.5 border-t border-border/50 pt-2">
              {thread.map((message) =>
                message.role === "user" ? (
                  <div
                    key={message.id}
                    className="ml-auto max-w-[85%] rounded-lg rounded-br-sm bg-primary px-2.5 py-1.5 text-[11px] font-medium text-primary-foreground"
                  >
                    {message.content}
                  </div>
                ) : (
                  <div key={message.id} className="flex items-start gap-1.5">
                    <div className="flex h-4 w-4 flex-none items-center justify-center rounded-full bg-primary text-[8px] font-bold text-primary-foreground mt-0.5">
                      W
                    </div>
                    <p className="rounded-lg rounded-tl-sm border border-border/60 bg-background/70 px-2.5 py-1.5 text-[11px] leading-snug text-foreground/90">
                      {message.content}
                    </p>
                  </div>
                )
              )}
              {isAIProcessing && (
                <p className="text-[10px] text-muted-foreground pl-1">
                  Wikily is thinking…
                </p>
              )}
            </div>
          )}

          {/* Inline "found in your wiki" search results */}
          {queryResults !== null && (
            <div className="space-y-1.5 border-t border-border/50 pt-2">
              <p className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
                Found in your wiki
              </p>
              {queryResults.length === 0 ? (
                <p className="text-[10px] text-muted-foreground">
                  No matches for “{querySubject}”.
                </p>
              ) : (
                queryResults.slice(0, 3).map((r) => (
                  <button
                    key={r.document.id}
                    type="button"
                    onClick={() => openLocalFile(r.document.id)}
                    className="block w-full rounded-lg border border-border/60 px-2.5 py-1.5 text-left hover:border-primary/50 hover:bg-muted/40"
                    title="Open this page"
                  >
                    <p className="flex items-center gap-1 text-[11px] font-semibold text-foreground">
                      <FileSearchIcon className="h-3 w-3 flex-none text-muted-foreground" />
                      {r.document.title}
                    </p>
                    <p className="text-[10px] leading-snug text-muted-foreground line-clamp-2">
                      {r.document.latestUpdate || r.document.summary}
                    </p>
                  </button>
                ))
              )}
            </div>
          )}

          {/* Quick-action row: Query the wiki, or run a saved prompt */}
          {(onSearch || (onQuickAction && quickActions.length > 0)) && (
            <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1 border-t border-border/50 pt-2">
              {onSearch && (
                <button
                  type="button"
                  onClick={runQuery}
                  className="flex items-center gap-1 text-[10px] font-semibold text-muted-foreground hover:text-foreground"
                >
                  <SearchIcon className="h-3 w-3" />
                  Query
                </button>
              )}
              {onQuickAction &&
                quickActions.slice(0, 2).map((action) => (
                  <button
                    key={action}
                    type="button"
                    onClick={() => runAction(action)}
                    className="text-[10px] font-semibold text-muted-foreground hover:text-foreground"
                  >
                    {action}
                  </button>
                ))}
            </div>
          )}

          {/* Ask Wikily / reply input */}
          {onQuickAction && (
            <div className="flex items-center gap-1.5 rounded-full border border-input bg-background/60 pl-3 pr-1 py-1">
              <Input
                value={askDraft}
                onChange={(e) => setAskDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    submitAsk();
                  }
                }}
                placeholder="Ask Wikily or type your own reply…"
                className="h-6 flex-1 border-0 bg-transparent p-0 text-[11px] shadow-none focus-visible:ring-0"
              />
              <Button
                size="icon"
                className="h-6 w-6 rounded-full flex-none"
                disabled={!askDraft.trim()}
                onClick={submitAsk}
                title="Send"
              >
                <SendIcon className="h-3 w-3" />
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
