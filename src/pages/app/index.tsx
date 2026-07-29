import {
  Card,
  DragButton,
  CustomCursor,
  Button,
  WikiCard,
} from "@/components";
import { AudioVisualizer, StatusIndicator } from "./components";
import { useApp } from "@/hooks";
import { useApp as useAppContext } from "@/contexts";
import { SparklesIcon, PlayIcon, AlertCircleIcon } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { ErrorBoundary } from "react-error-boundary";
import { ErrorLayout } from "@/layouts";
import { getPlatform } from "@/lib";
import { cn } from "@/lib/utils";

const App = () => {
  const { isHidden, systemAudio } = useApp();
  const {
    quickActions,
    handleQuickActionClick,
    conversation,
    isAIProcessing,
    lastTranscription,
    wikiSearch,
  } = systemAudio;
  const { customizable } = useAppContext();
  const platform = getPlatform();

  const openDashboard = async () => {
    try {
      await invoke("open_dashboard");
    } catch (error) {
      console.error("Failed to open dashboard:", error);
    }
  };

  return (
    <ErrorBoundary
      fallbackRender={() => {
        return <ErrorLayout isCompact />;
      }}
      resetKeys={["app-error"]}
      onReset={() => {
        console.log("Reset");
      }}
    >
      <div
        className={`w-screen h-screen flex overflow-hidden justify-center items-start ${
          isHidden ? "hidden pointer-events-none" : ""
        }`}
      >
        <Card className="w-full flex flex-row items-center gap-2 p-2">
          {systemAudio?.capturing ? (
            <div className="flex flex-row items-center gap-2 justify-between w-full">
              <div className="flex flex-1 items-center gap-2">
                <AudioVisualizer isRecording={systemAudio?.capturing} />
              </div>
              <div className="flex !w-fit items-center gap-2">
                <StatusIndicator
                  setupRequired={systemAudio.setupRequired}
                  error={systemAudio.error}
                  isProcessing={systemAudio.isProcessing}
                  isAIProcessing={systemAudio.isAIProcessing}
                />
              </div>
            </div>
          ) : null}

          <div
            className={`${
              systemAudio?.capturing
                ? "hidden w-full fade-out transition-all duration-300"
                : "w-full flex flex-row gap-2 items-center"
            }`}
          >
            <Button
              size={"icon"}
              className={cn(
                "cursor-pointer",
                systemAudio.setupRequired && "text-orange-500",
                systemAudio.error && !systemAudio.setupRequired && "text-red-500"
              )}
              title={
                systemAudio.setupRequired
                  ? "Setup required — click to grant access"
                  : systemAudio.error || "Start listening"
              }
              onClick={systemAudio.startCapture}
            >
              {systemAudio.setupRequired || systemAudio.error ? (
                <AlertCircleIcon className="h-4 w-4" />
              ) : (
                <PlayIcon className="h-4 w-4 fill-current" />
              )}
            </Button>
            <span className="flex-1 text-xs font-medium text-muted-foreground">
              {systemAudio.setupRequired
                ? "Grant access to start"
                : "Start listening"}
            </span>
            <Button
              size={"icon"}
              className="cursor-pointer"
              title="Open Wikily settings"
              onClick={openDashboard}
            >
              <SparklesIcon className="h-4 w-4" />
            </Button>
          </div>

          <DragButton />
        </Card>
        {/* Wikily: call-time HUD — the sole entry point for starting a call,
            not just its Q&A companion once one is underway. */}
        <WikiCard
          capturing={systemAudio.capturing}
          onStartCapture={systemAudio.startCapture}
          setupRequired={systemAudio.setupRequired}
          match={systemAudio.wikiMatch ?? null}
          onDismiss={systemAudio.dismissWikiMatch}
          onEngage={systemAudio.markWikiMatchClicked}
          quickActions={quickActions}
          onQuickAction={handleQuickActionClick}
          conversation={conversation}
          isAIProcessing={isAIProcessing}
          onSearch={wikiSearch}
          lastTranscription={lastTranscription}
          onStopCapture={systemAudio.stopCapture}
        />
        {customizable.cursor.type === "invisible" && platform !== "linux" ? (
          <CustomCursor />
        ) : null}
      </div>
    </ErrorBoundary>
  );
};

export default App;
