import {
  Theme,
  AutostartToggle,
  CheckForUpdatesToggle,
  UsageDataToggle,
  PermissionsSection,
} from "./components";
import { PageLayout } from "@/layouts";

const General = () => {
  return (
    <PageLayout title="General" description="App behavior and basics.">
      <div className="flex flex-col gap-6">
        <Theme />
        <AutostartToggle />
        <CheckForUpdatesToggle />
        <UsageDataToggle />
        <PermissionsSection />
      </div>
    </PageLayout>
  );
};

export default General;
