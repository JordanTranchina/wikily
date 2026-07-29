import { Behavior } from "./components";
import { PageLayout } from "@/layouts";

const BehaviorPage = () => {
  return (
    <PageLayout
      title="Behavior"
      description="Control how frequently Wikily speaks up, and how confident it must be to speak up."
    >
      <Behavior />
    </PageLayout>
  );
};

export default BehaviorPage;
