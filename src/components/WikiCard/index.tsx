import { Button, Badge } from "@/components";
import { useCopyToClipboard } from "@/hooks";
import { WikiMatch } from "@/lib/wiki";
import { openUrl, openPath } from "@tauri-apps/plugin-opener";
import {
  LightbulbIcon,
  CopyIcon,
  CheckIcon,
  ExternalLinkIcon,
  FileTextIcon,
  XIcon,
} from "lucide-react";

interface WikiCardProps {
  match: WikiMatch;
  onDismiss: () => void;
}

/**
 * Proactive Wikily HUD card (spec §3.3). Fades in over the active call when a
 * live transcript matches a local wiki page above the confidence threshold.
 */
export const WikiCard = ({ match, onDismiss }: WikiCardProps) => {
  const { document: doc, score } = match;

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

  const openLocalFile = async () => {
    try {
      await openPath(doc.id);
    } catch (err) {
      console.error("Failed to open wiki file:", err);
    }
  };

  return (
    <div className="absolute right-2 top-14 z-50 w-80 animate-in fade-in slide-in-from-top-2 duration-300">
      <div className="rounded-xl border border-secondary/40 bg-card/95 backdrop-blur-sm shadow-lg overflow-hidden">
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
              title="Dismiss"
              onClick={onDismiss}
            >
              <XIcon className="h-3 w-3" />
            </Button>
          </div>
        </div>

        <div className="px-3 pb-3 pt-2 space-y-1.5">
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
          <div className="flex flex-wrap items-center gap-1.5 pt-1">
            <Button
              size="sm"
              variant="outline"
              className="h-6 text-[10px] gap-1 px-2"
              onClick={handleCopy}
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
              onClick={openLocalFile}
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
                onClick={() => openUrl(link.url)}
                title={link.url}
              >
                <ExternalLinkIcon className="h-3 w-3" />
                {link.label.length > 18
                  ? link.label.slice(0, 18) + "…"
                  : link.label}
              </Button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
