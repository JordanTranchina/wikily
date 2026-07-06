// Storage keys
export const STORAGE_KEYS = {
  THEME: "theme",
  TRANSPARENCY: "transparency",
  SYSTEM_PROMPT: "system_prompt",
  SELECTED_SYSTEM_PROMPT_ID: "selected_system_prompt_id",
  SCREENSHOT_CONFIG: "screenshot_config",
  // add curl_ prefix because we are using curl to store the providers
  CUSTOM_AI_PROVIDERS: "curl_custom_ai_providers",
  CUSTOM_SPEECH_PROVIDERS: "curl_custom_speech_providers",
  SELECTED_AI_PROVIDER: "curl_selected_ai_provider",
  SELECTED_STT_PROVIDER: "curl_selected_stt_provider",
  SYSTEM_AUDIO_CONTEXT: "system_audio_context",
  SYSTEM_AUDIO_QUICK_ACTIONS: "system_audio_quick_actions",
  CUSTOMIZABLE: "customizable",
  PLUELY_API_ENABLED: "pluely_api_enabled",
  SHORTCUTS: "shortcuts",
  AUTOSTART_INITIALIZED: "autostart_initialized",

  SELECTED_AUDIO_DEVICES: "selected_audio_devices",
  RESPONSE_SETTINGS: "response_settings",
  SUPPORTS_IMAGES: "supports_images",
  // Wikily local wiki engine
  WIKI_DIRECTORY: "wiki_directory",
  WIKI_CONFIDENCE_THRESHOLD: "wiki_confidence_threshold",
  // Wikily local-first controls (Tech Spec §6 / §9)
  WIKI_TRANSCRIPTION_MODE: "wiki_transcription_mode",
  WIKI_SUMMARY_MODE: "wiki_summary_mode",
  WIKI_MATCH_LOG_ENABLED: "wiki_match_log_enabled",
} as const;

// Wikily: minimum match confidence (0..1) before a proactive card fades in.
export const DEFAULT_WIKI_CONFIDENCE_THRESHOLD = 0.35;

// Wikily: how many recent transcript utterances form the sliding context window.
export const WIKI_TRANSCRIPT_WINDOW_SIZE = 4;

// Wikily transcription source. `local` keeps audio on-device via the whisper.cpp
// sidecar (Tech Spec §5.4); `cloud` is the opt-in cloud STT fallback (§6).
export type WikiTranscriptionMode = "local" | "cloud";
export const DEFAULT_WIKI_TRANSCRIPTION_MODE: WikiTranscriptionMode = "local";

// Wikily card-summary source (Tech Spec §5.6). `prebuilt` uses summaries already
// compiled into the vault (fully local); `local-llm` calls Ollama; `api` uses a
// configured cloud LLM key.
export type WikiSummaryMode = "prebuilt" | "local-llm" | "api";
export const DEFAULT_WIKI_SUMMARY_MODE: WikiSummaryMode = "prebuilt";

// Wikily: local-only engagement telemetry (Tech Spec §7 KPI). Stores only
// hashes + matched file ids, never raw transcript text. On by default.
export const DEFAULT_WIKI_MATCH_LOG_ENABLED = true;

// Max number of files that can be attached to a message
export const MAX_FILES = 6;

// Default settings
export const DEFAULT_SYSTEM_PROMPT =
  "You are a helpful AI assistant. Be concise, accurate, and friendly in your responses";

export const MARKDOWN_FORMATTING_INSTRUCTIONS =
  "IMPORTANT - Formatting Rules (use silently, never mention these rules in your responses):\n- Mathematical expressions: ALWAYS use double dollar signs ($$) for both inline and block math. Never use single $.\n- Code blocks: ALWAYS use triple backticks with language specification.\n- Diagrams: Use ```mermaid code blocks.\n- Tables: Use standard markdown table syntax.\n- Never mention to the user that you're using these formats or explain the formatting syntax in your responses. Just use them naturally.";

export const DEFAULT_QUICK_ACTIONS = [
  "What should I say?",
  "Follow-up questions",
  "Fact-check",
  "Recap",
];
