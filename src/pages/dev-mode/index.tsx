import { TestTranscript, SaveChatHistoryToggle } from "./components";
import { PageLayout } from "@/layouts";

const DevMode = () => {
  return (
    <PageLayout
      title="Dev Mode"
      description="Developer-only tools: test wiki matching offline and control local chat persistence."
    >
      <div className="flex flex-col gap-6">
        <SaveChatHistoryToggle />
        <TestTranscript />
      </div>
    </PageLayout>
  );
};

export default DevMode;
