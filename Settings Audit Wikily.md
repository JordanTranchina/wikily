# Wikily settings audit — cut vs. keep

**Status: decisions finalized** via review comments on the [Notion copy](https://app.notion.com/p/jordantranchina/Settings-Audit-Wikily-3ab76ed4b97280f9a217e94ebd23efbf) on 2026-07-28. Every row below reflects the decided outcome, not a recommendation — where a decision reversed or refined the original recommendation, that's called out explicitly with the actual comment quoted.

**Purpose / background:** every setting/feature currently in the app, checked against `Product Spec Wikily.md` and the actual **"Wikily screen wireframes"** Claude Design project (`Wikily Wireframes.dc.html`, project `20abab4a-64c8-46a0-b13e-dd15d1aff026`). The design file contains exactly 3 screens: the Onboarding flow, the WikiCard HUD ("Live overlay during a Zoom call"), and Settings ("General, knowledge base, model, behavior & privacy" — exactly 4 tabs). Nothing else — no Chats, System Prompts, Responses, Screenshot, Cursor & Shortcuts, Dev Space, or standalone Wiki Engine page — appears anywhere in the design.

**Legend:** ✅ Keep · ❌ Cut · 🔀 Keep, relocated/reworked · 🆕 Build (in design, missing from app) · 🗑️ Delete (dead code) · 💬 Decision reverses or refines the original recommendation — see quoted comment

---

## Nav restructuring: split App Settings into standalone sidebar pages (implemented)

💬 *"Each of the tabs in 'App Settings' should be turned into their own sidebar nav item please."*

**Status: implemented.** Built exactly as planned below — purely structural, no content decisions elsewhere in this doc were touched by this change.

**Routes** (flat, matching every other page in the app — nothing else is nested): `/general`, `/knowledge-base`, `/model`, `/behavior`. `/settings` goes away entirely.

| New page | Replaces | `PageLayout` title / description |
|---|---|---|
| `src/pages/general/index.tsx` | `settings/components/General.tsx` | "General" / "App behavior and basics." — General has no page-level title today, this is a pure addition |
| `src/pages/knowledge-base/index.tsx` | `settings/components/KnowledgeBase.tsx` | "Knowledge base" / "Point Wikily at the docs it should learn from." — component already renders this exact title internally; that internal header gets removed so it isn't shown twice |
| `src/pages/model/index.tsx` | `settings/components/Model.tsx` | "Model" / "Choose the local model and transcription pipeline that power Wikily's suggestions." (crafted — no page-level title exists today, only the two sub-section headers "Transcription" and "Card summaries," which stay as-is) |
| `src/pages/behavior/index.tsx` | `settings/components/Behavior.tsx` | "Behavior" / "Control how frequently Wikily speaks up, and how confident it must be to speak up." — same dedupe as Knowledge base |

**Shared low-level pieces** (`Theme.tsx`, `AutostartToggle.tsx`, `AppIconToggle.tsx`, `AlwaysOnTopToggle.tsx`, `PermissionsSection.tsx`) move into `src/pages/general/components/` — only General composes them, confirmed nothing else in the codebase references them.

**`DeleteChats.tsx`** gets deleted as part of dismantling `settings/` rather than left orphaned with nowhere to live — it's already marked 🗑️ for deletion below, so this doesn't introduce a new decision.

**Sidebar wiring:**
- `useMenuItems.tsx` — the single "App Settings" entry (`Settings` icon, `/settings`) becomes 4 entries in the same list position: General (`Settings` icon, reused), Knowledge base (`LibraryIcon`), Model (`BrainIcon`), Behavior (`SlidersHorizontalIcon`). `LibraryIcon` avoids colliding with `BookOpenIcon`, already used for the separate Wiki Engine entry.
- `Sidebar.tsx` — the Wikily logo click currently does `navigate("/settings")`; repoints to `navigate("/general")` as the natural settings-home replacement.
- `routes/index.tsx` and `pages/index.ts` updated accordingly; `src/pages/settings/` deleted once the moves are done.

**Verification when implemented:** `npm run build` (tsc + vite build); confirm no other `/settings` string reference was missed beyond the 5 already identified (`Sidebar.tsx`, `useMenuItems.tsx`, `pages/index.ts`, `settings/index.tsx`, `routes/index.tsx`); optionally `npm run tauri dev` to visually confirm the 4 new sidebar entries navigate correctly with no duplicate titles on Knowledge base / Behavior.

---

## New: Dev Mode surface (to be built)

Two things survive specifically *because* they're moved behind a new developer-only surface that doesn't exist yet. This needs to be created. This is ok to create on the main sidebar nav for now:

- **"Test a Transcript" match tester** — moved here from the old Wiki Engine page. 💬 *"Agreed, aside from keeping test a transcript and moving it to a new developer page."* / *"Yeah let's do that please."*
- **"Save chat history locally" toggle** — gates whether `/chats` persists anything at all; off by default. 💬 *"Saving chats is fine as long as the user has turned on 'save chat history locally' in a dev mode tab (you'll likely need to create that)."*

---

## Sidebar nav — top level

| Nav item | Decision | Notes |
|---|---|---|
| Wiki Engine (`/wiki`) | ❌ Cut as a nav item | Duplicates Settings; its one non-duplicate feature (Test a Transcript) moves to the new Dev Mode surface, not gone entirely |
| App Settings (`/settings`) | ✅ Keep | Design-confirmed |
| Chats (`/chats`) | 🔀 Keep, gated | 💬 Reverses the "cut recommended" call — kept, but only persists when "Save chat history locally" is turned on in Dev Mode |
| System prompts (`/system-prompts`) | ❌ Cut | 💬 *"Agreed."* |
| Responses (`/responses`) | ❌ Cut | 💬 *"Agreed. Cut it."* |
| Screenshot (`/screenshot`) | ❌ Cut | 💬 *"Agreed"* |
| Audio (`/audio`) | ✅ Keep, trimmed | 💬 *"We can keep this tab but please remove the 'Tips' and the warning at the bottom please."* |
| Cursor & Shortcuts (`/shortcuts`) | ❌ Cut | 💬 *"Agreed. Cut it."* |
| Dev space (`/dev-space`) | ❌ Cut entirely | 💬 *"Just cut the whole tab. No need to keep the existing functionality here."* — reverses the earlier "fold BYOK into Model tab" recommendation; nothing here needs to survive |

---

## `/settings` — App Settings (design-confirmed screen)

### General tab

| Setting | File | Decision | Notes |
|---|---|---|---|
| Appearance / theme (light/dark/system) | `Theme.tsx` | ✅ Keep | Matches design row 1 |
| Window transparency slider | `Theme.tsx` | ✅ Keep | 💬 Reverses the original "cut" call — *"This is fine to keep actually."* |
| Launch on Startup | `AutostartToggle.tsx` | ✅ Keep | Matches design row 2 |
| Check for updates automatically | — | 🆕 Build | 💬 *"This is actually good to keep, though we'll likely change where the updates pull from in the future."* — build the toggle/row now; the update-source mechanism behind it may change later |
| Share anonymous usage data | Move from `Behavior.tsx`'s "Local match telemetry" | 🔀 Move + reword | 💬 *"I'm good with that."* — relocate into General, copy: *"Helps improve suggestion quality. Call transcripts are never included."* |
| App Icon Stealth Mode | `AppIconToggle.tsx` | ❌ Cut | 💬 *"Yep, delete it."* |
| Always On Top | `AlwaysOnTopToggle.tsx` | ❌ Cut the toggle, hardcode the behavior | 💬 *"Yeah it should just be hardcoded, not as a toggle. Hardcode to always on please."* — remove the setting/UI, but the window itself should always stay on top (no user control) |
| Permissions (Screen Recording, System Audio) | `PermissionsSection.tsx` | ✅ Keep | Matches design row 5 exactly |

### Knowledge base tab

| Setting | File | Decision | Notes |
|---|---|---|---|
| Directory picker / connect folder | `KnowledgeBase.tsx` | ✅ Keep | Matches design |
| Sync now / re-index | `KnowledgeBase.tsx` | ✅ Keep | Matches design |
| "N pages indexed · last synced X ago" | `KnowledgeBase.tsx` | ✅ Keep | Matches design |
| Extra "terms across N folders" badge | `KnowledgeBase.tsx` | ❌ Cut | 💬 *"Agreed. Cut it."* |
| "Wiki Engine" link-out card | `KnowledgeBase.tsx` | ❌ Cut | 💬 *"Agreed, cut it."* |

### Model tab — resolved

💬 Decision: *"Do this one. It doesn't have to be gemma models, but I've found Gemma to be quite good. For development purposes we can just use whatever local models have already been downloaded to my computer (gemma is at least one of them I believe)."*

**Rebuild toward the design's local model-size picker** (three radio cards — small/fast, recommended mid-size, large/high-accuracy — each with a size, a download/installed state, and a "Recommended" tag on the middle tier), replacing the current transcription-mode + summary-mode content. The model family doesn't have to be Gemma specifically; for development, wire it against whatever local models are already available/downloaded on the dev machine. This is real engineering scope (a local-model download/swap mechanism doesn't exist yet), not a settings-pruning change — worth scoping as its own follow-up piece of work rather than folding into a quick settings cleanup.

### Behavior tab

| Setting | File | Decision | Notes |
|---|---|---|---|
| Suggestion frequency (low/med/high) | `Behavior.tsx` | ✅ Keep | Matches design |
| Confidence threshold (low/med/high) | `Behavior.tsx` | ✅ Keep | Matches design |
| Local match telemetry toggle | `Behavior.tsx` | 🔀 Move out | 💬 *"Agreed, move it."* — relocates to General as "Share anonymous usage data" (see above) |

---

## `/wiki` — Wiki Engine (cut as a standalone page)

| Setting | Decision | Notes |
|---|---|---|
| Wiki directory picker | ❌ Cut (duplicate) | Owned by Settings → Knowledge base |
| Confidence threshold (as a % slider) | ❌ Cut (duplicate) | Owned by Settings → Behavior |
| Transcription mode toggle | ❌ Cut (duplicate) | Owned by Settings → Model |
| Card summary mode buttons | ❌ Cut (duplicate) | Owned by Settings → Model |
| Local match telemetry toggle | ❌ Cut (duplicate) | Owned by Settings → General (post-move) |
| "Test a Transcript" match tester | 🔀 Keep, relocated | 💬 *"Agreed, aside from keeping test a transcript and moving it to a new developer page."* — moves to the new Dev Mode surface, not deleted |

## `/audio` — Audio Settings (keep, trimmed)

💬 *"We can keep this tab but please remove the 'Tips' and the warning at the bottom please."*

| Setting | Decision | Notes |
|---|---|---|
| Microphone device selector | ✅ Keep | — |
| Output device selector | ✅ Keep | — |
| "💡 Tip:" copy under each device section | ❌ Cut | Both the mic and system-audio tip blocks in `AudioSelection.tsx` |
| Amber "⚠️ If selected devices don't work…" warning box | ❌ Cut | Bottom of `audio/index.tsx` |

## `/screenshot` — Screenshot settings (cut)

💬 *"Agreed"*

| Setting | Decision |
|---|---|
| Capture method (Selection vs. full Screenshot) | ❌ Cut |
| Processing mode (Auto vs. Manual) | ❌ Cut |
| Auto Prompt text field | ❌ Cut |

## `/shortcuts` — Cursor & Keyboard Shortcuts (cut)

💬 *"Agreed. Cut it."*

| Setting | Decision |
|---|---|
| Cursor type (invisible/default/auto) | ❌ Cut |
| Per-action keyboard shortcut manager + conflict detection + reset | ❌ Cut |

## `/responses` — Response Settings (cut)

💬 *"Agreed. Cut it."*

| Setting | Decision |
|---|---|
| Response length (short/auto/long) | ❌ Cut |
| Response language selector | ❌ Cut |
| Auto-scroll toggle | ❌ Cut |

## `/system-prompts` — System Prompts (cut)

💬 *"Agreed."*

| Setting | Decision |
|---|---|
| Create/edit/delete/select named AI behavior profiles | ❌ Cut |

## `/dev-space` — Dev space (cut entirely)

💬 *"Just cut the whole tab. No need to keep the existing functionality here."*

| Setting | Decision |
|---|---|
| AI Providers: curl-based custom LLM provider builder + API key mgmt | ❌ Cut, no replacement needed |
| STT Providers: same pattern for speech-to-text | ❌ Cut, no replacement needed |

Also worth noting: the main HUD's persistent button is labeled *"Open Dev Space"* (`src/pages/app/index.tsx:89`) but actually calls `open_dashboard`, which opens the general dashboard/Settings — stale copy independent of this audit, flagging in case it's news to the team.

## `/chats` + `/chats/view/:id` — Chats (keep, gated)

| Setting | Decision | Notes |
|---|---|---|
| Searchable history of manual queries | 🔀 Keep, gated | 💬 *"Saving chats is fine as long as the user has turned on 'save chat history locally' in a dev mode tab (you'll likely need to create that)."* — persistence only happens when that new Dev Mode toggle is on |
| "Delete Chat History" button | 🗑️ Delete | `DeleteChats.tsx` is dead code (exported, never rendered). 💬 *"Delete it"* |

---

## Not evaluated here (not "settings," out of this audit's scope)

- **WikiCard** (the HUD's Q&A thread, quick actions, ask-input) — one of the 3 design-confirmed screens, not a settings surface. Left alone.
- **Main HUD inline "Settings" panel** (`app/components/speech/SettingsPanel.tsx`) — VAD sensitivity presets/advanced tuning, system-prompt-vs-custom-context toggle. Embedded in the manual-search bar the spec's free floor keeps "unchanged from upstream Pluely" (§8). Left alone unless it should be brought into scope too.

---

## Net effect

**Sidebar:** App Settings, Audio (trimmed), Chats (gated) survive. System Prompts, Responses, Screenshot, Cursor & Shortcuts, Dev Space, and the standalone Wiki Engine page are all cut. A new hidden **Dev Mode** surface gets created to hold the Test-a-Transcript tool and the chat-history opt-in toggle.

**Settings tabs:** General gains "Check for updates automatically" (new) and "Share anonymous usage data" (relocated from Behavior); loses App Icon Stealth Mode and the Always-On-Top toggle (behavior hardcoded to on instead); keeps the transparency slider. Knowledge base loses the extra badge and the Wiki Engine link-out. Behavior loses the telemetry toggle (moved to General). Model tab gets rebuilt toward a local model-size picker — scoped as its own follow-up, not part of this cleanup pass.

**Dead code removed:** `DeleteChats.tsx`.

This document is now ready to drive implementation.
