import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components";
import { General, KnowledgeBase, Model, Behavior } from "./components";
import { PageLayout } from "@/layouts";

const Settings = () => {
  return (
    <PageLayout title="Settings" description="Manage your settings">
      <Tabs defaultValue="general">
        <TabsList>
          <TabsTrigger value="general">General</TabsTrigger>
          <TabsTrigger value="knowledge-base">Knowledge base</TabsTrigger>
          <TabsTrigger value="model">Model</TabsTrigger>
          <TabsTrigger value="behavior">Behavior</TabsTrigger>
        </TabsList>

        <TabsContent value="general" className="pt-4">
          <General />
        </TabsContent>
        <TabsContent value="knowledge-base" className="pt-4">
          <KnowledgeBase />
        </TabsContent>
        <TabsContent value="model" className="pt-4">
          <Model />
        </TabsContent>
        <TabsContent value="behavior" className="pt-4">
          <Behavior />
        </TabsContent>
      </Tabs>
    </PageLayout>
  );
};

export default Settings;
