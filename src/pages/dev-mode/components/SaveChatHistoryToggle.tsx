import { useState } from "react";
import { Switch, Label, Header } from "@/components";
import {
  getSaveChatHistoryEnabled,
  setSaveChatHistoryEnabled,
} from "@/lib/storage";

export const SaveChatHistoryToggle = ({ className }: { className?: string }) => {
  const [isEnabled, setIsEnabled] = useState(getSaveChatHistoryEnabled);

  const handleSwitchChange = (checked: boolean) => {
    setSaveChatHistoryEnabled(checked);
    setIsEnabled(checked);
  };

  return (
    <div className={`space-y-2 ${className}`}>
      <Header
        title="Save Chat History Locally"
        description="Controls whether Chats persists anything at all"
        isMainTitle
      />
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <div>
            <Label className="text-sm font-medium">
              {isEnabled ? "Chat history is saved" : "Chat history is off"}
            </Label>
            <p className="text-xs text-muted-foreground mt-1">
              {isEnabled
                ? "Conversations are persisted locally and appear under Chats"
                : "Off by default — conversations are never written to disk"}
            </p>
          </div>
        </div>
        <Switch
          checked={isEnabled}
          onCheckedChange={handleSwitchChange}
          aria-label="Toggle saving chat history locally"
        />
      </div>
    </div>
  );
};
