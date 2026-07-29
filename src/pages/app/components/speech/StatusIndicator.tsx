import { AlertCircleIcon, LoaderIcon } from "lucide-react";

type Props = {
  setupRequired: boolean;
  error: string;
  isProcessing: boolean;
  isAIProcessing: boolean;
};

export const StatusIndicator = ({
  setupRequired,
  error,
  isProcessing,
  isAIProcessing,
}: Props) => {
  // "Listening" itself is communicated by WikiCard's own idle pill now
  // (design screen "Live overlay during a Zoom call") — this row only needs
  // to interrupt with something WikiCard's pill doesn't already say.
  if (!error && !isAIProcessing && !isProcessing) return null;

  return (
    <div className="flex flex-1 items-center gap-2 px-3 py-2 justify-end">
      {/* Priority: Error > AI Processing > Transcribing */}
      {error && !setupRequired ? (
        <div className="flex items-center gap-2 text-red-600">
          <AlertCircleIcon className="w-4 h-4" />
          <span className="text-xs font-medium">{error}</span>
        </div>
      ) : isAIProcessing ? (
        <div className="flex items-center gap-2 animate-pulse">
          <LoaderIcon className="w-4 h-4 animate-spin" />
          <span className="text-xs font-medium">Generating response...</span>
        </div>
      ) : isProcessing ? (
        <div className="flex items-center gap-2 animate-pulse">
          <LoaderIcon className="w-4 h-4 animate-spin" />
          <span className="text-xs font-medium">Transcribing...</span>
        </div>
      ) : null}
    </div>
  );
};
