import { useState } from "react";
import { Header, Button, Badge } from "@/components";
import { useWiki } from "@/hooks";
import { open } from "@tauri-apps/plugin-dialog";
import { Link } from "react-router-dom";
import moment from "moment";
import {
  FolderOpenIcon,
  RefreshCwIcon,
  LoaderIcon,
  AlertCircleIcon,
  ArrowRightIcon,
} from "lucide-react";

/**
 * The everyday "which folder am I pointed at" surface — the full engine
 * (confidence testing, transcription/summary mode) lives on the dedicated
 * Wiki Engine page, linked below.
 */
export const KnowledgeBase = () => {
  const {
    directory,
    setDirectory,
    isIndexing,
    stats,
    lastIndexedAt,
    error,
    scanAndIndex,
  } = useWiki();
  const [isChanging, setIsChanging] = useState(false);

  const handleChange = async () => {
    try {
      const picked = await open({
        directory: true,
        multiple: false,
        title: "Select your local wiki directory",
      });
      if (typeof picked === "string") {
        setIsChanging(true);
        setDirectory(picked);
        await scanAndIndex(picked);
        setIsChanging(false);
      }
    } catch (err) {
      console.error("Directory picker failed:", err);
      setIsChanging(false);
    }
  };

  const handleSync = () => scanAndIndex(directory);

  return (
    <div id="knowledge-base" className="flex flex-col gap-6">
      <div className="space-y-3">
        <Header
          title="Knowledge base"
          description="Point Wikily at the docs it should learn from."
          isMainTitle
        />

        {!directory ? (
          <div className="flex items-center justify-between gap-4 rounded-lg border border-dashed border-border p-4">
            <div>
              <p className="text-sm font-medium">No folder connected yet</p>
              <p className="text-xs text-muted-foreground">
                Run the setup wizard to connect a folder of notes or wiki
                pages.
              </p>
            </div>
            <Button asChild size="sm" className="gap-1.5 flex-none">
              <Link to="/onboarding">
                Connect
                <ArrowRightIcon className="h-3.5 w-3.5" />
              </Link>
            </Button>
          </div>
        ) : (
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-3 rounded-lg border border-dashed border-border bg-muted/20 px-3 py-2.5 font-mono text-xs">
              <span className="truncate" title={directory}>
                {directory}
              </span>
              <button
                type="button"
                onClick={handleChange}
                disabled={isChanging || isIndexing}
                className="flex-none text-[11px] font-sans font-semibold text-muted-foreground hover:text-foreground"
              >
                Change…
              </button>
            </div>

            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              {isIndexing || isChanging ? (
                <span className="flex items-center gap-1.5">
                  <LoaderIcon className="h-3.5 w-3.5 animate-spin" />
                  Indexing…
                </span>
              ) : error ? (
                <span className="flex items-center gap-1.5 text-red-600">
                  <AlertCircleIcon className="h-3.5 w-3.5" />
                  {error}
                </span>
              ) : stats ? (
                <span>
                  <strong className="text-foreground">
                    {stats.documentCount}
                  </strong>{" "}
                  pages indexed
                  {lastIndexedAt && (
                    <> · last synced {moment(lastIndexedAt).fromNow()}</>
                  )}
                </span>
              ) : null}
              <Button
                size="sm"
                variant="ghost"
                className="h-6 gap-1 px-2 text-[11px]"
                onClick={handleSync}
                disabled={isIndexing || isChanging}
              >
                <RefreshCwIcon className="h-3 w-3" />
                Sync now
              </Button>
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between gap-4 rounded-lg border border-border/50 p-3">
        <div>
          <p className="text-sm font-medium">Wiki Engine</p>
          <p className="text-xs text-muted-foreground">
            Advanced: test how a transcript matches your wiki, page by page.
          </p>
        </div>
        <Button asChild size="sm" variant="outline" className="gap-1.5 flex-none">
          <Link to="/wiki">
            <FolderOpenIcon className="h-3.5 w-3.5" />
            Open
          </Link>
        </Button>
      </div>
      {directory && stats && (
        <Badge variant="secondary" className="w-fit text-[10px]">
          {stats.tokenCount} terms across {stats.scannedDirs} folders
        </Badge>
      )}
    </div>
  );
};
