import { KnowledgeBase } from "./components";
import { PageLayout } from "@/layouts";

const KnowledgeBasePage = () => {
  return (
    <PageLayout
      title="Knowledge base"
      description="Point Wikily at the docs it should learn from."
    >
      <KnowledgeBase />
    </PageLayout>
  );
};

export default KnowledgeBasePage;
