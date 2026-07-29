import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { CheckIcon } from "lucide-react";
import { useWiki } from "@/hooks";

/**
 * Closes out the "connect → index" flow with a toast the moment indexing
 * finishes (design screen "Wiki setup"), rather than making the user watch a
 * progress bar. Mounted once in DashboardLayout so it surfaces regardless of
 * which page is active when indexing completes.
 */
export const IndexingToast = () => {
  const { isIndexing, stats, error } = useWiki();
  const [visible, setVisible] = useState(false);
  const wasIndexing = useRef(false);

  useEffect(() => {
    const justFinished = wasIndexing.current && !isIndexing;
    wasIndexing.current = isIndexing;
    if (justFinished && stats && !error) {
      setVisible(true);
      const timer = setTimeout(() => setVisible(false), 6000);
      return () => clearTimeout(timer);
    }
  }, [isIndexing, stats, error]);

  if (!visible || !stats) return null;

  return (
    <div className="fixed bottom-4 right-4 z-50 flex items-center gap-2.5 rounded-xl bg-foreground px-3.5 py-2.5 text-background shadow-lg animate-in fade-in slide-in-from-bottom-2 duration-300">
      <span className="flex h-4.5 w-4.5 items-center justify-center rounded-full bg-green-500 text-background">
        <CheckIcon className="h-3 w-3" />
      </span>
      <span className="text-xs font-medium">
        {stats.documentCount} pages indexed
      </span>
      <Link
        to="/knowledge-base"
        onClick={() => setVisible(false)}
        className="text-xs font-semibold text-primary-foreground/80 underline hover:text-background"
      >
        View
      </Link>
    </div>
  );
};
