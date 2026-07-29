import { Header } from "@/components";
import { useWiki } from "@/hooks";
import { WikiSummaryMode } from "@/config";
import { CheckIcon, CpuIcon, CloudIcon } from "lucide-react";
import { cn } from "@/lib/utils";

const SUMMARY_MODES: {
  value: WikiSummaryMode;
  label: string;
  hint: string;
}[] = [
  {
    value: "prebuilt",
    label: "Prebuilt summaries",
    hint: "Use summaries already written into your wiki pages — no model needed, fully local.",
  },
  {
    value: "local-llm",
    label: "Local LLM",
    hint: "Generate the card summary on-device via Ollama. Nothing leaves your machine.",
  },
  {
    value: "api",
    label: "Cloud API",
    hint: "Generate the summary with your configured cloud AI provider.",
  },
];

/**
 * Which model powers Wikily's on-call suggestions. Local-first by default —
 * cloud is opt-in (Product Spec §6).
 */
export const Model = () => {
  const { transcriptionMode, setTranscriptionMode, summaryMode, setSummaryMode } =
    useWiki();

  return (
    <div className="flex flex-col gap-6">
      <div className="space-y-3">
        <Header
          title="Transcription"
          description="Where audio-to-text runs during a call."
          isMainTitle
        />
        <div className="space-y-2">
          {(
            [
              {
                value: "local" as const,
                icon: CpuIcon,
                label: "On-device (whisper.cpp)",
                hint: "Recommended — audio never leaves your machine. Falls back to cloud only if you've configured it and the local model is missing.",
              },
              {
                value: "cloud" as const,
                icon: CloudIcon,
                label: "Cloud speech provider",
                hint: "Uses your configured cloud STT provider for every call.",
              },
            ]
          ).map((opt) => {
            const selected = transcriptionMode === opt.value;
            const Icon = opt.icon;
            return (
              <button
                key={opt.value}
                type="button"
                onClick={() => setTranscriptionMode(opt.value)}
                className={cn(
                  "flex w-full items-start gap-3 rounded-lg border p-3 text-left transition-colors",
                  selected
                    ? "border-primary bg-primary/5"
                    : "border-border/60 hover:border-border"
                )}
              >
                <div
                  className={cn(
                    "mt-0.5 flex h-4 w-4 flex-none items-center justify-center rounded-full border",
                    selected
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-muted-foreground/40"
                  )}
                >
                  {selected && <CheckIcon className="h-2.5 w-2.5" />}
                </div>
                <Icon className="mt-0.5 h-4 w-4 flex-none text-muted-foreground" />
                <div>
                  <p className="text-sm font-semibold">{opt.label}</p>
                  <p className="text-xs text-muted-foreground">{opt.hint}</p>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <div className="space-y-3">
        <Header
          title="Card summaries"
          description="How the 2-sentence status summary on a suggestion card is produced."
          isMainTitle
        />
        <div className="space-y-2">
          {SUMMARY_MODES.map((m) => {
            const selected = summaryMode === m.value;
            return (
              <button
                key={m.value}
                type="button"
                onClick={() => setSummaryMode(m.value)}
                className={cn(
                  "flex w-full items-start gap-3 rounded-lg border p-3 text-left transition-colors",
                  selected
                    ? "border-primary bg-primary/5"
                    : "border-border/60 hover:border-border"
                )}
              >
                <div
                  className={cn(
                    "mt-0.5 flex h-4 w-4 flex-none items-center justify-center rounded-full border",
                    selected
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-muted-foreground/40"
                  )}
                >
                  {selected && <CheckIcon className="h-2.5 w-2.5" />}
                </div>
                <div>
                  <p className="text-sm font-semibold">{m.label}</p>
                  <p className="text-xs text-muted-foreground">{m.hint}</p>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
