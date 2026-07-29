import { STORAGE_KEYS } from "@/config";
import { safeLocalStorage } from "./helper";

export const getCheckForUpdatesEnabled = (): boolean => {
  const stored = safeLocalStorage.getItem(STORAGE_KEYS.CHECK_FOR_UPDATES_ENABLED);
  return stored === null ? true : stored === "true";
};

export const setCheckForUpdatesEnabled = (enabled: boolean): void => {
  safeLocalStorage.setItem(STORAGE_KEYS.CHECK_FOR_UPDATES_ENABLED, String(enabled));
};
