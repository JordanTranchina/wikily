import { useCallback, useEffect, useState } from "react";
import { Header, Button, Badge } from "@/components";
import { invoke } from "@tauri-apps/api/core";
import { getPlatform } from "@/lib";
import { CheckCircle2Icon, ExternalLinkIcon } from "lucide-react";

type PermissionStatus = "checking" | "granted" | "not-granted";

/**
 * macOS-only permission rows Wikily needs to see (Screen Recording) and hear
 * (System Audio Recording) a call. Each row's "Open System Settings" button
 * hands off to the real OS permission dialog — Wikily never assumes access.
 */
export const PermissionsSection = () => {
  const platform = getPlatform();
  const [screenRecording, setScreenRecording] =
    useState<PermissionStatus>("checking");
  const [systemAudio, setSystemAudio] = useState<PermissionStatus>("checking");

  const checkScreenRecording = useCallback(async () => {
    if (platform !== "macos") return;
    try {
      const { checkScreenRecordingPermission } = await import(
        "tauri-plugin-macos-permissions-api"
      );
      const granted = await checkScreenRecordingPermission();
      setScreenRecording(granted ? "granted" : "not-granted");
    } catch {
      setScreenRecording("not-granted");
    }
  }, [platform]);

  const checkSystemAudio = useCallback(async () => {
    try {
      const granted = await invoke<boolean>("check_system_audio_access");
      setSystemAudio(granted ? "granted" : "not-granted");
    } catch {
      setSystemAudio("not-granted");
    }
  }, []);

  useEffect(() => {
    checkScreenRecording();
    checkSystemAudio();
  }, [checkScreenRecording, checkSystemAudio]);

  const openScreenRecordingSettings = async () => {
    try {
      const { requestScreenRecordingPermission } = await import(
        "tauri-plugin-macos-permissions-api"
      );
      await requestScreenRecordingPermission();
    } finally {
      setTimeout(checkScreenRecording, 1500);
    }
  };

  const openSystemAudioSettings = async () => {
    try {
      await invoke("request_system_audio_access");
    } finally {
      setTimeout(checkSystemAudio, 1500);
    }
  };

  if (platform !== "macos") return null;

  const rows: {
    key: string;
    label: string;
    help: string;
    status: PermissionStatus;
    onOpen: () => void;
  }[] = [
    {
      key: "screen-recording",
      label: "Screen Recording",
      help: "Lets Wikily read what's on your screen during a call.",
      status: screenRecording,
      onOpen: openScreenRecordingSettings,
    },
    {
      key: "system-audio",
      label: "System Audio Recording",
      help: "Lets Wikily hear call audio to generate suggestions.",
      status: systemAudio,
      onOpen: openSystemAudioSettings,
    },
  ];

  return (
    <div id="permissions" className="space-y-3">
      <Header
        title="Permissions"
        description="Wikily needs these macOS permissions to see and hear your calls."
        isMainTitle
      />
      <div className="space-y-2">
        {rows.map((row) => (
          <div
            key={row.key}
            className="flex items-start justify-between gap-4 rounded-lg border border-border/50 p-3"
          >
            <div className="space-y-0.5">
              <p className="text-sm font-medium">{row.label}</p>
              <p className="text-xs text-muted-foreground">{row.help}</p>
            </div>
            {row.status === "granted" ? (
              <Badge
                variant="secondary"
                className="gap-1 flex-none text-[10px]"
              >
                <CheckCircle2Icon className="h-3 w-3 text-green-500" />
                Granted
              </Badge>
            ) : (
              <Button
                size="sm"
                variant="outline"
                className="gap-1 flex-none text-xs"
                onClick={row.onOpen}
              >
                Open System Settings
                <ExternalLinkIcon className="h-3 w-3" />
              </Button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};
