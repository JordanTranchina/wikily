# Technical Specification: Wikily (MVP)

**Status:** Draft v1 · **Target Release:** Q3 2026 · **Owner:** Engineering
**Companion doc:** [`Product Spec Wikily.md`](./Product%20Spec%20Wikily.md)
**Upstream:** Fork of [Pluely](https://github.com/iamsrikanthnani/pluely) v0.1.9

---

## 1. Overview & Scope

Wikily is a proactive macOS overlay for customer-facing teams on live Zoom calls. It captures the
call audio, transcribes it locally, semantically matches the rolling transcript against a
pre-compiled local markdown "LLM wiki," and fades context cards into a floating HUD — local-first,
with no call audio leaving the machine.

This document specifies **how** the product spec is implemented against the **actual Wikily/Pluely
codebase**. It covers the architecture, the modules to reuse, the modules to build, data models,
performance budgets, and a milestone-by-milestone engineering plan. It is intentionally grounded:
every reused component is cited by file path so engineers can navigate directly to it.

**In scope (MVP):** local audio capture, local streaming transcription, local markdown indexing,
local semantic matching, proactive HUD cards, copy/deep-link actions, settings to point at a wiki
directory.

**Out of scope (MVP):** Notion cloud sync (post-MVP roadmap), multi-language wiki compilation, team
sync, analytics dashboards beyond what Pluely already ships.

---

## 2. ⚠️ Stack Correction (Read First)

The product spec repeatedly describes Wikily as a **Swift / SwiftUI** application using **NSPanel**,
**ScreenCaptureKit**, and **CoreAudio** written natively in Swift. **This is inaccurate and must not
drive engineering decisions.**

Wikily is a fork of Pluely, and **Pluely is a [Tauri v2](https://tauri.app) application**, not a
native Swift app. The real stack is:

| Layer | Product spec (incorrect) | **Actual implementation** |
|---|---|---|
| App framework | Swift / SwiftUI | **Tauri v2** (Rust core + web frontend) |
| UI | SwiftUI views | **React 19 + TypeScript + Tailwind CSS 4** (`src/`) |
| Floating HUD | Native `NSPanel` in Swift | **`tauri-nspanel`** bound from Rust (`src-tauri/src/lib.rs:213`) |
| System audio | ScreenCaptureKit | **`cidre` (CoreAudio)** on macOS, `wasapi` on Windows, `libpulse` on Linux (`src-tauri/src/speaker/`) |
| Screen capture | ScreenCaptureKit | **`xcap`** crate (`src-tauri/src/capture.rs`) |
| Backend logic | Swift | **Rust** (`src-tauri/src/`, Tokio async) |
| Persistence | (unspecified) | **SQLite** via `tauri-plugin-sql` (`src-tauri/src/db/`) |

The good news: the *capabilities* the product spec relies on (a floating panel that stays above
full-screen Zoom, dual-stream audio capture, global shortcuts, markdown rendering) **all already
exist** in this codebase — just implemented in Rust + React rather than Swift. Wikily reuses them as
described in §4 and adds the wiki/matching engine in §5.

The native macOS panel *is* an `NSPanel` under the hood — `tauri-nspanel` calls the same AppKit APIs
(`NSFloatWindowLevel`, `NSWindowStyleMaskNonActivatingPanel`, full-screen-auxiliary collection
behavior; see `src-tauri/src/lib.rs:241-256`). So the product spec's UX intent holds; only the
implementation language differs.

---

## 3. System Architecture

### 3.1 High-level component diagram

```
┌───────────────────────────── Tauri App (single process) ─────────────────────────────┐
│                                                                                        │
│   React + TypeScript Frontend (src/)            Rust Core (src-tauri/src/)              │
│   ┌──────────────────────────────┐     IPC      ┌────────────────────────────────────┐ │
│   │  HUD / Overlay UI            │  commands &   │  Audio Capture + VAD (speaker/)    │ │
│   │  pages/app, components/      │  events       │  cidre / wasapi / libpulse         │ │
│   │  Overlay.tsx                 │ <───────────> │                                    │ │
│   │                              │               │  Transcription                     │ │
│   │  Settings + Wiki picker      │               │   ├─ Local: whisper.cpp (NEW)      │ │
│   │  pages/settings, audio       │               │   └─ Cloud: api.rs transcribe (✓)  │ │
│   │                              │               │                                    │ │
│   │  Markdown render             │               │  Wiki Engine (NEW: wiki/)          │ │
│   │  components/Markdown         │               │   ├─ Scanner + MD parser           │ │
│   └──────────────────────────────┘               │   ├─ Embeddings (fastembed/ONNX)   │ │
│                                                   │   └─ Vector index + cosine match   │ │
│                                                   │                                    │ │
│   tauri-nspanel float panel ◄──── proactive ──── │  Match Orchestrator (NEW)          │ │
│   (lib.rs:213 init)            trigger event      │                                    │ │
│                                                   │  SQLite (db/) · tauri-plugin-sql   │ │
│                                                   └────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                              Local filesystem: ~/.../MyKnowledgeWiki/*.md
```

### 3.2 End-to-end data flow (the "full loop")

1. **Capture.** Rust `start_system_audio_capture` (`src-tauri/src/speaker/commands.rs:47`) taps the
   system output (incoming Zoom = `[Client]`); the mic stream is captured in parallel (`[User]`).
   VAD (`VadConfig`, `commands.rs:18`) gates on speech and emits WAV buffers.
2. **Transcribe.** Each utterance buffer is transcribed. Local-first path → bundled whisper.cpp
   sidecar (NEW). Fallback path → existing cloud STT (`transcribe_audio`, `src-tauri/src/api.rs`).
   Output: speaker-tagged transcript segments emitted to the frontend / match orchestrator.
3. **Window.** The Match Orchestrator (NEW) keeps a sliding 15–30 s transcript window.
4. **Embed + match.** The window is embedded and compared (cosine similarity) against the local wiki
   vector index; entity/keyword hits (`Becky promotion`, error codes) boost the score.
5. **Trigger.** If `score ≥ threshold`, the orchestrator emits a `wikily://card` event with the
   matched node payload.
6. **Render.** The React HUD observer receives the event, fades the `tauri-nspanel` window in, and
   renders the context card (title, status, 2-sentence summary, quick links).

### 3.3 Concurrency model

The Rust core is Tokio-async (`tokio = { features = ["full"] }`, `src-tauri/Cargo.toml`). Audio
capture, transcription, and matching run on background tasks; results reach the UI via Tauri's
`Emitter` event bus (already used throughout `speaker/commands.rs`). The match index lives in a
shared `Arc<RwLock<…>>` state object registered with `app.manage(...)`, mirroring the existing
`AudioState` pattern.

---

## 4. Reused Components (Inherited from Pluely)

These ship today and require **integration/redirection only**, not rewriting.

| Capability | Where | Notes for Wikily |
|---|---|---|
| System + mic audio capture, VAD | `src-tauri/src/speaker/{commands,macos,windows,linux}.rs` | Run two capture streams (system = Client, mic = User). `VadConfig` defaults at `commands.rs:31` are a good starting point. WAV via `hound`. |
| Floating macOS panel | `src-tauri/src/lib.rs:213-257` | `to_panel()`, float level, non-activating, full-screen-auxiliary + can-join-all-spaces. This is the HUD window. |
| Window positioning / dynamic height | `src-tauri/src/window.rs` | Card height changes → `set_window_height`. |
| Global shortcuts | `src-tauri/src/shortcuts.rs` + `@tauri-apps/plugin-global-shortcut` | Optional manual "show last card" hotkey. |
| Cloud STT abstraction (fallback) | `src/lib/functions/stt.function.ts`, `src/lib/storage/stt-providers.ts`, `src-tauri/src/api.rs` | Becomes the cloud fallback path (§6). Curl-templated, multi-provider. |
| LLM abstraction (summary) | `src/lib/functions/ai-response.function.ts`, `src/lib/storage/ai-providers.ts`, `src/pages/dev/` | Used by the optional card-summary generator (Ollama/local or API). |
| Markdown rendering | `src/components/Markdown/` (Streamdown + Shiki + KaTeX) | Renders card body and full wiki-page preview. |
| SQLite + migrations | `src-tauri/src/db/`, `src/lib/database/` | Extend with wiki tables (§5.7). |
| Settings & local storage | `src/pages/{settings,audio}/`, `src/lib/storage/` | Add wiki-directory picker + thresholds. |
| Frontend VAD | `@ricky0123/vad-react` | Optional UI-side gating / visualizer. |
| Secure secrets | `tauri-plugin-keychain`, `src-tauri/src/activate.rs` | API keys for cloud fallback stay in Keychain. |

---

## 5. New Components (The Wikily Engine)

All new Rust code lives under a new module tree `src-tauri/src/wiki/`; new frontend lives under
`src/pages/wiki/` and `src/lib/wiki/`.

### 5.1 Wiki directory picker & scanner
- **Frontend:** add a directory picker to settings (`src/pages/settings/`), persisting the chosen
  path to local storage (`src/lib/storage/`). Use `@tauri-apps/plugin-dialog` (add dependency).
- **Rust (`wiki/scanner.rs`):** Tauri command `scan_wiki_dir(path)` that recursively walks `.md`
  files, parsing:
  - YAML frontmatter (`serde_yaml`) → title, tags, status, links, source URL (e.g. Notion).
  - Headers (`#`/`##`) → section anchors for sub-page deep links.
  - Inline `#tags` and `[[wikilinks]]` → entity/cross-reference graph.
- **Output:** a `WikiFile { id, path, title, frontmatter, sections[], tags[], links[] }` list,
  persisted to SQLite and chunked for embedding.
- **Budget:** index 100+ files in well under the product-spec target (§7).

### 5.2 Local embeddings & vector index
- **Rust (`wiki/embed.rs`):** embed each chunk (section-level) with a small on-device model.
  - **Recommended:** [`fastembed`](https://crates.io/crates/fastembed) (ONNX Runtime, ships
    quantized `bge-small`/`all-MiniLM` ~384-dim) — pure-Rust integration, CPU-fast on Apple Silicon.
  - **Alternative:** `candle` + a CoreML/Metal backend if we want Neural-Engine acceleration.
- **Index (`wiki/index.rs`):** in-memory `Vec<(chunk_id, Vec<f32>)>` for the live path, mirrored to
  SQLite (`wiki_embeddings`) so re-scans are incremental (hash each file; only re-embed changed
  files). For 100s–low-1000s of chunks, brute-force cosine is sub-millisecond; no ANN library needed
  for MVP (revisit with `hnsw_rs` only if the vault grows large).

### 5.3 Semantic match orchestrator
- **Rust (`wiki/match.rs`):** maintains the sliding transcript window (last 15–30 s, time-boxed
  `VecDeque`, same pattern as the audio buffers in `commands.rs:8`).
- On each new transcript segment: embed the window, compute cosine similarity vs. the index:

  ```
  score(q, d) = (q · d) / (‖q‖ · ‖d‖)
  ```

  where `q` = window embedding, `d` = chunk embedding.
- **Entity boost:** exact/fuzzy matches of extracted entities (project names like "Becky promotion",
  product names, error codes) against `wiki_files.title` / `tags` add a weighted bonus, so
  proper-noun queries resolve reliably even when semantic similarity is mid-range.
- **Trigger:** emit `wikily://card` when `final_score ≥ threshold` (default configurable, product
  spec implies a high-confidence gate). Debounce so the same card doesn't re-fire every segment.

### 5.4 Local transcription (whisper.cpp)
- **Goal path:** bundle [`whisper.cpp`](https://github.com/ggerganov/whisper.cpp) with CoreML /
  Metal acceleration as a Tauri **sidecar** binary (declared in `tauri.conf.json`
  `bundle.externalBin`, invoked via `tauri-plugin-shell`, already a dependency — see
  `commands.rs:14`). Stream WAV utterance buffers in; receive text out.
  - Recommended model for streaming latency: `base.en` / `small.en` quantized.
- **Speaker tagging:** the source stream determines the tag (system output → `[Client]`, mic →
  `[User]`) — no diarization model needed for MVP.
- **Fallback:** if local model is absent/disabled, route to cloud STT (§6).
- **Budget:** partial transcript < ~2 s after utterance (§7).

### 5.5 Proactive HUD card system
- **Frontend (`src/pages/app/` + new `src/pages/wiki/Card.tsx`):** a background observer subscribes
  to `wikily://card`. On receipt it:
  - Fades the panel from transparent → visible (CSS transition; panel already always-on-top).
  - Renders the card: **Title**, **Status**, **Latest update** (2-sentence summary), **Key blocker**,
    **Quick links** (`[Copy Status]`, `[Open Notion ↗]`, `[Open local .md ↗]`).
  - Auto-dismiss / pin controls.
- **Actions:** copy-to-clipboard (Tauri clipboard), deep-link via `@tauri-apps/plugin-opener`
  (already used in `src/components/Markdown/`) to open the local file or remote URL from frontmatter.
- **Manual fallback:** Pluely's existing manual trigger remains available for low-confidence cases.

### 5.6 Optional card-summary generator
- When a matched node is large, generate the 2-sentence summary on demand via the existing LLM
  abstraction (`ai-response.function.ts`), pointed at **Ollama/local** by default to preserve
  local-first, or a configured API key. If the wiki was pre-compiled Karpathy-style (summaries
  already in frontmatter), this step is skipped — use the stored summary directly.

### 5.7 Data model (new SQLite tables)
Add a migration under `src-tauri/src/db/` (follows the existing `conversations`/`messages` pattern):

| Table | Key columns |
|---|---|
| `wiki_files` | `id`, `path`, `content_hash`, `title`, `status`, `source_url`, `frontmatter_json`, `updated_at` |
| `wiki_chunks` | `id`, `file_id` → `wiki_files.id`, `section_anchor`, `text`, `char_range` |
| `wiki_embeddings` | `chunk_id` → `wiki_chunks.id`, `dim`, `vector` (BLOB f32) |
| `match_log` (opt, local-only telemetry) | `id`, `ts`, `window_text_hash`, `matched_file_id`, `score`, `clicked` (for KPI §7) |

**localStorage keys (frontend):** `WIKILY_WIKI_DIR`, `WIKILY_MATCH_THRESHOLD`,
`WIKILY_TRANSCRIPTION_MODE` (`local`|`cloud`), `WIKILY_SUMMARY_MODE` (`prebuilt`|`local-llm`|`api`).

---

## 6. Local-First vs. Cloud Fallback

The product spec mandates **100% local-first**: call audio and transcripts must never reach a remote
server. The current codebase ships cloud STT/LLM providers and an optional Pluely cloud relay. The
MVP reconciles these as a **local-first default with an explicit, opt-in cloud fallback**.

| Concern | Local-first (default) | Cloud fallback (opt-in) |
|---|---|---|
| Transcription | whisper.cpp sidecar (§5.4) | `transcribe_audio` cloud STT (`api.rs`) |
| Embeddings | `fastembed` on-device (§5.2) | — (always local) |
| Card summary | Ollama / prebuilt frontmatter | Configured API key (OpenAI/Claude/…) |
| Network | none | only the chosen provider endpoint |

**Hard requirements:**
- Pluely's optional cloud relay must be **off by default** for Wikily. Gate any remote call on the
  existing `PLUELY_API_ENABLED` flag (defaults false) and surface a clear settings toggle.
- When `WIKILY_TRANSCRIPTION_MODE = local`, the cloud STT code path is never invoked; audio buffers
  stay in process memory and are not persisted to disk beyond the transient WAV.
- Transcripts are kept in memory (sliding window) and are **not** written to the chat-history DB by
  default. `match_log` (if enabled) stores only hashes + matched IDs, never raw transcript text.
- API keys (fallback only) remain in the macOS Keychain (`tauri-plugin-keychain`).

---

## 7. Performance Budgets

| Metric (from product spec) | Target | How met |
|---|---|---|
| Transcript latency | text within ~2 s of utterance | whisper.cpp `base.en`/`small.en` quantized on Apple Silicon; VAD-gated short buffers |
| HUD fade-in | card visible within **1.5 s** of the trigger utterance | embedding + brute-force cosine over a few-thousand chunks is sub-ms; panel is pre-warmed and always-on-top, so only a CSS fade remains |
| Wiki indexing | 100+ files indexed fast | incremental hash-based scan + batched embedding; only changed files re-embed |
| Match accuracy | resolves "Becky promotion" → correct node, offline | semantic cosine + entity/keyword boost on titles/tags |
| App footprint | stay lean (Pluely is ~10 MB) | sidecar model is the main addition; ship quantized models, lazy-load |

---

## 8. Implementation Milestones

Mirrors the product spec's M1–M5, expressed as engineering tasks against real files, plus a
cloud-fallback interim that de-risks the local-model work.

### M1 — Validate dual-stream capture (fork sanity)
- Build the Tauri app; confirm `start_system_audio_capture` (`speaker/commands.rs:47`) feeds the
  system output, and add a parallel mic capture stream.
- **Done when:** both `[Client]` and `[User]` WAV buffers land in memory with no feedback loop.

### M2 — Transcription pipeline (cloud first, then local)
- *M2a (fast):* wire both audio streams into the existing cloud STT (`api.rs` / `stt.function.ts`),
  print speaker-tagged transcript to console. Validates the data flow end-to-end.
- *M2b (local):* add the whisper.cpp sidecar (`tauri.conf.json` `externalBin`, `tauri-plugin-shell`),
  swap to local by default. **Done when:** continuous `[Client]`/`[User]` transcript prints < ~2 s.

### M3 — Wiki reader & index
- Add directory picker to `src/pages/settings/`; implement `wiki/scanner.rs` + `wiki/embed.rs` +
  migration (§5.7). **Done when:** a 100+ file vault scans, parses frontmatter/headers/tags, and
  produces a persisted vector index within budget.

### M4 — Semantic match
- Implement `wiki/match.rs` (sliding window + cosine + entity boost). **Done when:** a mock
  transcript "Where are we on the Becky promotion?" resolves `Project: Becky Promotion Campaign`
  with a high similarity score, fully offline.

### M5 — Proactive HUD (full loop)
- Wire the `wikily://card` event to the panel observer + `Card.tsx`; fade in on threshold.
  **Done when:** speaking the target query (with simulated client audio) fades the HUD in within
  1.5 s, rendering the status card with copy + deep-link actions.

---

## 9. Security & Privacy

- **On-device by default:** with local transcription + local embeddings, no call audio, transcript,
  or wiki content leaves the machine.
- **No remote relay:** Pluely cloud sync stays disabled (`PLUELY_API_ENABLED = false`) unless the
  user explicitly opts into a cloud fallback provider.
- **Minimal persistence:** transcripts live only in the in-memory sliding window; nothing transcript-
  derived is persisted except optional hashed `match_log` rows for the engagement KPI.
- **Secrets:** any fallback API keys are stored in the macOS Keychain via `tauri-plugin-keychain`.
- **Filesystem scope:** the app reads only the user-selected wiki directory.
- **Permissions:** macOS mic + system-audio capture prompts handled by
  `tauri-plugin-macos-permissions` (already wired in `lib.rs:205`).

---

## 10. Open Questions & Risks

1. **Embedding model choice** — `fastembed`/ONNX (simple, CPU) vs `candle` + CoreML (Neural-Engine
   accel). Recommend starting with `fastembed`, benchmark, upgrade only if needed.
2. **whisper.cpp packaging** — sidecar binary size, code-signing/notarization of the bundled binary,
   CoreML model download-on-first-run vs bundled. Needs a build-pipeline spike.
3. **Platform scope** — capture/index/match are cross-platform, but the proactive float-panel UX is
   macOS-only (`#[cfg(target_os = "macos")]`, `lib.rs:213`). MVP targets macOS 14+ Apple Silicon;
   Windows/Linux HUD parity is post-MVP.
4. **Sliding-window noise** — overlapping speakers / cross-talk may produce spurious matches; tune
   VAD (`VadConfig`) and the confidence threshold; debounce re-fires.
5. **Wiki compilation assumption** — the engine assumes a pre-compiled Karpathy-style vault with
   summaries. A "compile my vault" pipeline is implied but **out of MVP scope** (note for roadmap
   alongside Notion sync).
6. **Notion sync (post-MVP)** — OAuth → workspace export → compile to local markdown; deferred per
   product spec §6.

---

## 11. Appendix

### 11.1 Key file index (citations)
- Floating panel init: `src-tauri/src/lib.rs:213-257`
- Audio capture + VAD: `src-tauri/src/speaker/commands.rs` (config `:18`, command `:47`)
- Platform audio: `src-tauri/src/speaker/{macos,windows,linux}.rs`
- Window mgmt: `src-tauri/src/window.rs`
- Shortcuts: `src-tauri/src/shortcuts.rs`
- Cloud STT/LLM orchestration: `src-tauri/src/api.rs`
- DB migrations: `src-tauri/src/db/`
- STT frontend: `src/lib/functions/stt.function.ts`, `src/lib/storage/stt-providers.ts`
- LLM frontend: `src/lib/functions/ai-response.function.ts`, `src/lib/storage/ai-providers.ts`
- Markdown render: `src/components/Markdown/`
- Settings/audio UI: `src/pages/settings/`, `src/pages/audio/`
- Rust deps: `src-tauri/Cargo.toml` (`cidre`, `tauri-nspanel`, `xcap`, `hound`, `tauri-plugin-sql`, `tokio`)

### 11.2 New modules to create
- Rust: `src-tauri/src/wiki/{mod,scanner,embed,index,match}.rs`
- Frontend: `src/pages/wiki/Card.tsx`, `src/lib/wiki/`, wiki-dir picker in `src/pages/settings/`
- Migration: new file under `src-tauri/src/db/`
- New deps: `fastembed` (or `candle`), `serde_yaml`, `@tauri-apps/plugin-dialog`; whisper.cpp sidecar

### 11.3 Glossary
- **HUD / overlay** — the always-on-top floating panel (`tauri-nspanel`).
- **Sliding window** — last 15–30 s of transcript used as the match query.
- **Entity boost** — score bonus when a proper noun in the transcript matches a wiki title/tag.
- **Sidecar** — an external binary bundled with and launched by the Tauri app.
- **Local-first** — all processing on-device by default; cloud is strictly opt-in.
