import { Theme } from "./Theme";
import { AutostartToggle } from "./AutostartToggle";
import { AppIconToggle } from "./AppIconToggle";
import { AlwaysOnTopToggle } from "./AlwaysOnTopToggle";
import { PermissionsSection } from "./PermissionsSection";

export const General = () => {
  return (
    <div className="flex flex-col gap-6">
      <Theme />
      <AutostartToggle />
      <AppIconToggle />
      <AlwaysOnTopToggle />
      <PermissionsSection />
    </div>
  );
};
