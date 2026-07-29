import { Switch, Label, Header } from "@/components";
import { useWiki } from "@/hooks";

export const UsageDataToggle = ({ className }: { className?: string }) => {
  const { matchLogEnabled, setMatchLogEnabled } = useWiki();

  return (
    <div className={`space-y-2 ${className}`}>
      <Header
        title="Share Anonymous Usage Data"
        description="Helps improve suggestion quality. Call transcripts are never included."
        isMainTitle
      />
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <div>
            <Label className="text-sm font-medium">
              {matchLogEnabled ? "Sharing enabled" : "Sharing disabled"}
            </Label>
            <p className="text-xs text-muted-foreground mt-1">
              Tracks how often you copy/open a surfaced card, stored locally as
              hashes only.
            </p>
          </div>
        </div>
        <Switch
          checked={matchLogEnabled}
          onCheckedChange={setMatchLogEnabled}
          aria-label="Toggle anonymous usage data sharing"
        />
      </div>
    </div>
  );
};
