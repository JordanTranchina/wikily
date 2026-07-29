import {
  Settings,
  MessagesSquare,
  AudioLinesIcon,
  PowerIcon,
  MailIcon,
  CoffeeIcon,
  GlobeIcon,
  BugIcon,
  TerminalIcon,
  LibraryIcon,
  BrainIcon,
  SlidersHorizontalIcon,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { XIcon, GithubIcon } from "@/components";

export const useMenuItems = () => {
  const menu: {
    icon: React.ElementType;
    label: string;
    href: string;
    count?: number;
  }[] = [
    {
      icon: MessagesSquare,
      label: "Chats",
      href: "/chats",
    },
    {
      icon: Settings,
      label: "General",
      href: "/general",
    },
    {
      icon: LibraryIcon,
      label: "Knowledge base",
      href: "/knowledge-base",
    },
    {
      icon: BrainIcon,
      label: "Model",
      href: "/model",
    },
    {
      icon: SlidersHorizontalIcon,
      label: "Behavior",
      href: "/behavior",
    },
    {
      icon: AudioLinesIcon,
      label: "Audio",
      href: "/audio",
    },
    {
      icon: TerminalIcon,
      label: "Dev Mode",
      href: "/dev-mode",
    },
  ];

  const footerItems = [
    {
      icon: MailIcon,
      label: "Contact Support",
      href: "mailto:support@pluely.com",
    },
    {
      icon: BugIcon,
      label: "Report a bug",
      href: "https://github.com/iamsrikanthnani/pluely/issues/new?template=bug-report.yml",
    },
    {
      icon: PowerIcon,
      label: "Quit Wikily",
      action: async () => {
        await invoke("exit_app");
      },
    },
  ];

  const footerLinks: {
    title: string;
    icon: React.ElementType;
    link: string;
  }[] = [
    {
      title: "Website",
      icon: GlobeIcon,
      link: "https://pluely.com",
    },
    {
      title: "Github",
      icon: GithubIcon,
      link: "https://github.com/iamsrikanthnani/pluely",
    },
    {
      title: "Buy Me a Coffee",
      icon: CoffeeIcon,
      link: "https://buymeacoffee.com/srikanthnani",
    },
    {
      title: "Follow on X",
      icon: XIcon,
      link: "https://x.com/srikanthnani",
    },
  ];

  return {
    menu,
    footerItems,
    footerLinks,
  };
};
