import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { open } from "@tauri-apps/plugin-dialog";
import { Button, Card } from "@/components";
import { useWiki } from "@/hooks";
import {
  FolderSearchIcon,
  FolderOpenIcon,
  LoaderIcon,
  SparklesIcon,
} from "lucide-react";

type Step = "connect" | "indexing";

/**
 * First-run wiki setup wizard (design screen "Wiki setup — connect & build in
 * the background"). Connects a local folder, hands the user back to the app
 * immediately, and lets indexing finish on its own — the dashboard layout
 * surfaces a toast the moment it's ready (see `components/IndexingToast`).
 */
const Onboarding = () => {
  const navigate = useNavigate();
  const { setDirectory, scanAndIndex } = useWiki();
  const [step, setStep] = useState<Step>("connect");
  const [path, setPath] = useState("");
  const [isPicking, setIsPicking] = useState(false);

  const handleBrowse = async () => {
    setIsPicking(true);
    try {
      const picked = await open({
        directory: true,
        multiple: false,
        title: "Select your local wiki directory",
      });
      if (typeof picked === "string") {
        setPath(picked);
        setDirectory(picked);
        // Kick off indexing in the background — the user doesn't wait on it.
        void scanAndIndex(picked);
        setStep("indexing");
      }
    } catch (err) {
      console.error("Directory picker failed:", err);
    } finally {
      setIsPicking(false);
    }
  };

  return (
    <div className="flex h-screen w-screen items-center justify-center bg-background">
      <Card className="w-full max-w-md p-8 text-center">
        <div className="mx-auto mb-2 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          {step === "connect" ? (
            <FolderSearchIcon className="h-6 w-6" />
          ) : (
            <SparklesIcon className="h-6 w-6" />
          )}
        </div>

        {step === "connect" ? (
          <>
            <h1 className="text-lg font-bold">Connect your knowledge base</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Point Wikily at a folder of notes, docs, or wiki pages — we'll
              index it so answers surface automatically during calls.
            </p>
            <div className="mt-6 flex items-center gap-2 rounded-lg border border-dashed border-border bg-muted/20 px-3 py-2.5 text-left font-mono text-xs text-muted-foreground">
              <FolderOpenIcon className="h-3.5 w-3.5 flex-none" />
              <span className="truncate">
                {path || "Choose a folder…"}
              </span>
            </div>
            <Button
              className="mt-4 w-full gap-1.5"
              onClick={handleBrowse}
              disabled={isPicking}
            >
              {isPicking ? (
                <LoaderIcon className="h-4 w-4 animate-spin" />
              ) : (
                <FolderOpenIcon className="h-4 w-4" />
              )}
              Browse…
            </Button>
          </>
        ) : (
          <>
            <h1 className="text-lg font-bold">
              We'll build this in the background
            </h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Keep working — Wikily is indexing your files now and will let
              you know the moment it's ready.
            </p>
            <Button
              className="mt-6 w-full"
              onClick={() => navigate("/knowledge-base")}
            >
              Continue to Wikily
            </Button>
          </>
        )}
      </Card>
    </div>
  );
};

export default Onboarding;
