import { useState } from "react";
import { Button, Badge, Input } from "@/components";
import { useCopyToClipboard } from "@/hooks";
import { ChatConversation } from "@/hooks";
import { WikiMatch } from "@/lib/wiki";
import { PermissionFlow } from "@/pages/app/components/speech/PermissionFlow";
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
  SquareIcon,
} from "lucide-react";

interface WikiCardProps {
  /** Whether a call is currently being captured. Drives the pill's idle
   * "start a session" state vs. the live listening/Q&A state (design screen
   * "Live overlay during a Zoom call"). */
  capturing: boolean;
  /** Starts a new capture session — the idle pill's play button. */
  onStartCapture?: () => void;
  /** True when macOS permissions still need to be granted before capture can start. */
  setupRequired?: boolean;
  /** The current proactive match, if any. Null while Wikily is listening but
   * hasn't surfaced a suggestion yet — the card still renders as the call's
   * always-available Q&A companion. */
  match: WikiMatch | null;
  /** Clears the current match only — has no effect when `match` is null. */
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
  /** Ends the call capture entirely (the top pill's stop button). */
  onStopCapture?: () => void;
}

/**
 * Wikily's call-time HUD (design screen "Live overlay during a Zoom call").
 * Renders the whole time a call is being captured — not just when a
 * proactive match fires — as an idle "Wikily is listening" pill that expands
 * into a persistent Q&A panel (quick actions, a running thread, and
 * on-device wiki search). A proactive match, when one fires, is inserted as
 * a distinct suggestion block rather than being the card's only reason to
 * exist (spec §3.3).
 */
export const WikiCard = ({
  capturing,
  onStartCapture,
  setupRequired,
  match,
  onDismiss,
  onEngage,
  quickActions = [],
  onQuickAction,
  conversation,
  isAIProcessing,
  onSearch,
  lastTranscription,
  onStopCapture,
}: WikiCardProps) => {
  const doc = match?.document;
  const score = match?.score;
  const [collapsed, setCollapsed] = useState(false);
  const [askDraft, setAskDraft] = useState("");
  const [queryResults, setQueryResults] = useState<WikiMatch[] | null>(null);
  const [querySubject, setQuerySubject] = useState("");

  // Build a copy-friendly status blob.
  const copyText = doc
    ? [
        doc.title,
        doc.status ? `Status: ${doc.status}` : "",
        doc.latestUpdate ? `Latest: ${doc.latestUpdate}` : "",
        doc.blocker ? `Blocker: ${doc.blocker}` : "",
      ]
        .filter(Boolean)
        .join("\n")
    : "";

  const { isCopied, handleCopy } = useCopyToClipboard({ text: copyText });

  const handleCopyAndTrack = () => {
    onEngage?.();
    handleCopy();
  };

  const openLocalFile = async (path?: string) => {
    const target = path ?? doc?.id;
    if (!target) return;
    onEngage?.();
    try {
      await openPath(target);
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
    const subject = lastTranscription?.trim() || doc?.title;
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

  // Not capturing: the compact bar's own inline play button (app/index.tsx)
  // is the entry point — it's always inside the 54px idle window, unlike
  // this overlay, which only becomes visible once the window has grown (see
  // useSystemAudio's resize effect, keyed off `capturing`/`setupRequired`).
  // Once that click flips `setupRequired`, the window grows and this
  // permission flow becomes reachable.
  if (!capturing) {
    if (!setupRequired) return null;
    return (
      <div className="absolute right-2 top-14 z-[60] w-80 animate-in fade-in slide-in-from-top-2 duration-300">
        <PermissionFlow
          onPermissionGranted={() => onStartCapture?.()}
          onPermissionDenied={() => {}}
        />
      </div>
    );
  }

  // Idle top pill (design's "Wikily is listening") when there's no match to
  // show a title for; a matched doc still gets its own title in the pill.
  if (collapsed) {
    return (
      <div className="absolute right-2 top-14 z-[60] animate-in fade-in slide-in-from-top-1 duration-200">
        <div className="flex items-center gap-2 rounded-full border border-border/60 bg-card/95 backdrop-blur-md shadow-lg px-3 py-1.5">
          {doc ? (
            <>
              <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground flex-none">
                W
              </div>
              <span
                className="text-xs font-medium max-w-[10rem] truncate"
                title={doc.title}
              >
                {doc.title}
              </span>
            </>
          ) : (
            <>
              <span className="relative flex h-2 w-2 flex-none">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-500 opacity-60" />
                <span className="relative inline-flex h-2 w-2 rounded-full bg-green-500" />
              </span>
              <span className="text-xs font-medium">Wikily is listening</span>
            </>
          )}
          <button
            type="button"
            className="text-muted-foreground hover:text-foreground"
            title="Show"
            onClick={() => setCollapsed(false)}
          >
            <ChevronDownIcon className="h-3.5 w-3.5" />
          </button>
          {onStopCapture && (
            <>
              <div className="h-3.5 w-px bg-border flex-none" />
              <button
                type="button"
                className="text-muted-foreground hover:text-red-500"
                title="Stop"
                onClick={onStopCapture}
              >
                <SquareIcon className="h-2.5 w-2.5 fill-current" />
              </button>
            </>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="absolute right-2 top-14 z-[60] w-80 animate-in fade-in slide-in-from-top-2 duration-300">
      <div className="rounded-xl border border-secondary/40 bg-card/95 backdrop-blur-md shadow-lg overflow-hidden">
        {/* Pill header — Wikily branding + Hide/Show + Stop, always present */}
        <div className="flex items-center justify-between gap-2 px-3 pt-3">
          <div className="flex items-center gap-1.5 min-w-0">
            {doc ? (
              <>
                <LightbulbIcon className="h-4 w-4 text-amber-500 flex-shrink-0" />
                <span
                  className="text-xs font-semibold truncate"
                  title={doc.title}
                >
                  {doc.title}
                </span>
                <Badge
                  variant="secondary"
                  className="text-[9px] px-1.5 py-0 h-4 flex-none"
                  title="Match confidence"
                >
                  {Math.round((score ?? 0) * 100)}%
                </Badge>
              </>
            ) : (
              <>
                <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground flex-none">
                  W
                </div>
                <span className="text-xs font-semibold">Wikily</span>
              </>
            )}
          </div>
          <div className="flex items-center gap-1.5 flex-shrink-0 text-muted-foreground">
            <button
              type="button"
              className="flex items-center gap-0.5 text-[10px] font-semibold hover:text-foreground"
              title="Hide"
              onClick={() => setCollapsed(true)}
            >
              Hide
              <ChevronUpIcon className="h-3 w-3" />
            </button>
            {onStopCapture && (
              <>
                <div className="h-3.5 w-px bg-border flex-none" />
                <button
                  type="button"
                  className="hover:text-red-500"
                  title="Stop"
                  onClick={onStopCapture}
                >
                  <SquareIcon className="h-2.5 w-2.5 fill-current" />
                </button>
              </>
            )}
            {doc && (
              <Button
                size="icon"
                variant="ghost"
                className="h-5 w-5"
                title="Dismiss suggestion"
                onClick={onDismiss}
              >
                <XIcon className="h-3 w-3" />
              </Button>
            )}
          </div>
        </div>

        <div className="px-3 pb-3 pt-2 space-y-2">
          {/* Status */}
          {doc?.status && (
            <div className="flex items-center gap-1.5">
              <span className="text-[10px] text-muted-foreground">Status:</span>
              <Badge className="text-[9px] px-1.5 py-0 h-4">{doc.status}</Badge>
            </div>
          )}

          {/* Suggestion details — only when a proactive match has fired */}
          {doc && (
            <>
              <p className="text-[11px] leading-snug text-foreground/90">
                {doc.latestUpdate || doc.summary}
              </p>

              {doc.blocker && (
                <p className="text-[10px] leading-snug text-muted-foreground">
                  <span className="font-medium">Blocker:</span> {doc.blocker}
                </p>
              )}

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
            </>
          )}

          {/* Idle empty state — no suggestion yet, no thread yet */}
          {!doc && thread.length === 0 && queryResults === null && (
            <p className="text-[11px] leading-snug text-muted-foreground">
              Ask a question, or keep talking — Wikily will surface a
              suggestion here if something in your wiki matches.
            </p>
          )}

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
