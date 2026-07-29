import { Model } from "./components";
import { PageLayout } from "@/layouts";

const ModelPage = () => {
  return (
    <PageLayout
      title="Model"
      description="Choose the local model and transcription pipeline that power Wikily's suggestions."
    >
      <Model />
    </PageLayout>
  );
};

export default ModelPage;
