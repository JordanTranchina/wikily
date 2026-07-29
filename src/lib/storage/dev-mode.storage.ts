import { STORAGE_KEYS } from "@/config";
import { safeLocalStorage } from "./helper";

export const getSaveChatHistoryEnabled = (): boolean => {
  return safeLocalStorage.getItem(STORAGE_KEYS.DEV_SAVE_CHAT_HISTORY) === "true";
};

export const setSaveChatHistoryEnabled = (enabled: boolean): void => {
  safeLocalStorage.setItem(STORAGE_KEYS.DEV_SAVE_CHAT_HISTORY, String(enabled));
};
