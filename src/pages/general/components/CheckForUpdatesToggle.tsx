import { useState } from "react";
import { Switch, Label, Header } from "@/components";
import {
  getCheckForUpdatesEnabled,
  setCheckForUpdatesEnabled,
} from "@/lib/storage";

export const CheckForUpdatesToggle = ({ className }: { className?: string }) => {
  const [isEnabled, setIsEnabled] = useState(getCheckForUpdatesEnabled);

  const handleSwitchChange = (checked: boolean) => {
    setCheckForUpdatesEnabled(checked);
    setIsEnabled(checked);
  };

  return (
    <div className={`space-y-2 ${className}`}>
      <Header
        title="Check for Updates Automatically"
        description="Wikily checks for a new version on launch"
        isMainTitle
      />
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <div>
            <Label className="text-sm font-medium">
              {isEnabled ? "Automatic checks on" : "Automatic checks off"}
            </Label>
            <p className="text-xs text-muted-foreground mt-1">
              {isEnabled
                ? "Wikily will check for updates every time it launches"
                : "You can still check manually from the updater icon"}
            </p>
          </div>
        </div>
        <Switch
          checked={isEnabled}
          onCheckedChange={handleSwitchChange}
          aria-label="Toggle automatic update checks"
        />
      </div>
    </div>
  );
};
