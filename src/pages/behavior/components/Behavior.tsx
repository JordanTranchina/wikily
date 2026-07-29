import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components";
import { useWiki } from "@/hooks";
import {
  WikiSuggestionFrequency,
  WIKI_CONFIDENCE_PRESETS,
} from "@/config";

const FREQUENCY_OPTIONS: { value: WikiSuggestionFrequency; label: string }[] =
  [
    { value: "low", label: "Low" },
    { value: "medium", label: "Medium" },
    { value: "high", label: "High" },
  ];

/** Nearest named preset for whatever raw threshold is currently stored. */
const closestPreset = (threshold: number): keyof typeof WIKI_CONFIDENCE_PRESETS => {
  let best: keyof typeof WIKI_CONFIDENCE_PRESETS = "medium";
  let bestDiff = Infinity;
  (Object.keys(WIKI_CONFIDENCE_PRESETS) as (keyof typeof WIKI_CONFIDENCE_PRESETS)[]).forEach(
    (key) => {
      const diff = Math.abs(WIKI_CONFIDENCE_PRESETS[key] - threshold);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = key;
      }
    }
  );
  return best;
};

/**
 * Controls how frequently Wikily surfaces a suggestion, and how confident it
 * must be to speak up (design screen "Settings — Behavior").
 */
export const Behavior = () => {
  const { suggestionFrequency, setSuggestionFrequency, threshold, setThreshold } =
    useWiki();

  return (
    <div className="flex flex-col gap-6">
      <div className="divide-y divide-border/50 rounded-lg border border-border/50">
        <div className="flex items-center justify-between gap-4 p-3">
          <div>
            <p className="text-sm font-medium">Suggestion frequency</p>
            <p className="text-xs text-muted-foreground">
              How often Wikily surfaces a suggestion
            </p>
          </div>
          <Select
            value={suggestionFrequency}
            onValueChange={(v) =>
              setSuggestionFrequency(v as WikiSuggestionFrequency)
            }
          >
            <SelectTrigger className="w-[150px] flex-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {FREQUENCY_OPTIONS.map((opt) => (
                <SelectItem key={opt.value} value={opt.value}>
                  {opt.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="flex items-center justify-between gap-4 p-3">
          <div>
            <p className="text-sm font-medium">Confidence threshold</p>
            <p className="text-xs text-muted-foreground">
              Minimum confidence required before showing a suggestion
            </p>
          </div>
          <Select
            value={closestPreset(threshold)}
            onValueChange={(v) =>
              setThreshold(
                WIKI_CONFIDENCE_PRESETS[v as keyof typeof WIKI_CONFIDENCE_PRESETS]
              )
            }
          >
            <SelectTrigger className="w-[150px] flex-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {FREQUENCY_OPTIONS.map((opt) => (
                <SelectItem key={opt.value} value={opt.value}>
                  {opt.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
    </div>
  );
};
