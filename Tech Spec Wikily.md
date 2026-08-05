# Technical Specification: Wikily (Native macOS)

**Status:** Reflects the shipping architecture · **Owner:** Engineering
**Companion doc:** [`Product Spec Wikily.md`](./Product%20Spec%20Wikily.md)
**Roadmap / merge status:** [`docs/NATIVE_REWRITE_ROADMAP.md`](./docs/NATIVE_REWRITE_ROADMAP.md)

---

## 1. Overview & Scope

Wikily is a proactive macOS overlay for customer-facing teams on live Zoom calls. It captures
call audio, transcribes it entirely on-device, semantically matches the rolling transcript
against a local markdown "LLM wiki," and fades context cards into a floating HUD — local-first,
with no call audio or transcript ever leaving the machine.

This document specifies **how** the product spec is implemented against the **actual codebase**,
which lives under `Wikily/` (a hand-authored Xcode project, target `Wikily`) and is a from-scratch
**native Swift / AppKit / SwiftUI** application — not a fork of anything. It covers the
architecture, the module breakdown, data models, performance characteristics, and how the build
got here. Every component is cited by real file path so engineers can navigate directly to it.

**In scope (shipped):** local dual-stream audio capture, local on-device streaming transcription,
local markdown wiki indexing (with incremental re-scan), local TF-IDF semantic matching, a
proactive floating HUD with quick actions and grounded Q&A ("Ask Wikily"), a full Settings app,
first-run onboarding, persistence, opt-in Google/Outlook calendar sync with a "meeting starts in
1 minute" reminder (§6, §4's Calendar row, `docs/CALENDAR_INTEGRATION.md`).

**Out of scope (post-MVP):** Notion cloud sync, multi-language wiki compilation, team sync,
engagement analytics beyond local logging.

---

## 2. Why Native Swift, Not the Tauri Fork the Product Spec Describes

Earlier drafts of this project were scoped as a fork of [Pluely](https://github.com/iamsrikanthnani/pluely)
(a Tauri v2 / Rust / React desktop app) — reusing its floating-panel and audio-capture plumbing
and adding a local wiki-matching engine on top. **That plan was abandoned.** The `Product Spec`
still describes that strategy in places (its "Pluely Fork" framing, §1.3–1.5, §3.1, §3.3, §4); it
is a historical artifact of that earlier scoping, not what shipped.

What actually got built is a ground-up native macOS app: Swift 6, AppKit for the window/menu-bar
layer, SwiftUI for the HUD and Settings content hosted inside AppKit windows. Reasons this ended
up cleaner than the fork:

- **The audio and HUD code Pluely would have contributed still had to be redone.** Pluely's
  `tauri-nspanel` panel and `cidre`-based CoreAudio tap are real capabilities, but a `.nonactivatingPanel`
  `NSPanel` and a native CoreAudio process tap are not large to write directly in Swift, and doing
  so avoids two IPC layers (Tauri's Rust↔JS bridge, plus whatever bridges Rust CoreAudio bindings)
  between "audio arrived" and "the HUD updates."
- **On-device transcription got dramatically simpler.** The fork plan needed a bundled
  `whisper.cpp` sidecar binary, a model download/bundling pipeline, and its own code-signing story
  (see the old `docs/LOCAL_TRANSCRIPTION.md`, now rewritten). Apple's `SpeechAnalyzer`/
  `SpeechTranscriber` APIs do on-device transcription natively, with the OS itself managing model
  download and storage — no sidecar, no bundling step, no separate signing concern.
  `Transcription/SpeechModelInstaller.swift`.
- **No embeddings model needed.** The fork plan called for `fastembed`/ONNX vector embeddings and
  a vector index. The actual matcher is plain TF-IDF cosine similarity (`Wiki/WikiMatcher.swift`,
  `Wiki/WikiIndex.swift`) — proven equivalent to a reference TypeScript implementation to 6
  decimal places over a fixture vault, and empirically "impressively robust to transcription
  noise" (a misheard "OAuth" → "OOS" still scored 94% from surrounding words). No ONNX runtime,
  no model download, no GPU/Neural-Engine dependency for matching.
- **No SQLite.** Settings persist through `UserDefaults` via `AppState/AppSettings.swift`; the wiki
  index cache persists as JSON in Application Support (`Wiki/WikiIndexCache.swift`) — the whole
  cache is read/written as a unit, there are no queries to make, and a corrupt file costs one
  re-parse rather than a migration story.

The net effect: fewer moving parts than the fork would have had, not more. 242 tests, 23 suites,
all logic-level (no UI test target), `xcodebuild test`.

---

## 3. System Architecture

### 3.1 High-level component diagram

```
┌────────────────────────────── Wikily.app (single process) ───────────────────────────────┐
│                                                                                             │
│  AppDelegate (WikilyApp.swift)                                                             │
│   ├─ AppMainMenu.swift            — full AppKit menu bar (App/Edit/Session/Window/Help)    │
│   ├─ MenuBarController.swift      — NSStatusItem, the app's primary control surface        │
│   ├─ OverlayWindowController.swift → OverlayPanel.swift (NSPanel, floating HUD)            │
│   │      hosts SwiftUI content: Overlay/OverlayView.swift                                  │
│   └─ CallSession (AppState/CallSession.swift) — orchestrates everything below              │
│                                                                                             │
│  CallSession                                                                               │
│   ├─ CallCaptureSession (Audio/)          — mic + system-audio capture, VAD, event stream  │
│   │    ├─ SystemAudioTap.swift            — CoreAudio process tap + aggregate device        │
│   │    ├─ MicrophoneCapture.swift                                                          │
│   │    └─ VoiceActivityDetector.swift                                                      │
│   ├─ SpeechAnalyzerTranscriber (Transcription/) — on-device streaming transcription        │
│   ├─ WikiMatchCoordinator (Wiki/)          — sliding window, confidence gate, debounce      │
│   │    └─ WikiMatcher + WikiIndex (Wiki/)  — TF-IDF cosine similarity                       │
│   └─ AskSession (Chat/)                    — grounded Q&A over the matched page + transcript│
│                                                                                             │
│  AppSettings (AppState/) — UserDefaults-backed, namespaced keys, single source of truth     │
│  SettingsWindowController / SettingsRootView (Settings/) — AppKit window, SwiftUI panes     │
│  OnboardingWindowController / OnboardingView (Onboarding/) — first-run wizard               │
└──────────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                              Local filesystem: user-chosen wiki folder (*.md)
                              + Application Support: WikiIndexCache JSON, on-device speech model
```

### 3.2 End-to-end data flow (the "full loop")

1. **Capture.** `CallCaptureSession` (an `actor`) starts `SystemAudioTap` (incoming call audio —
   `[Client]`) and `MicrophoneCapture` (`[User]`) in parallel via a CoreAudio aggregate device +
   process tap. Each source also runs through `VoiceActivityDetector` for the cheap
   "someone is speaking" signal the HUD's live indicator uses, and to segment WAV dumps for
   diagnostics — but the continuous stream, not VAD-segmented chunks, is what feeds transcription:
   `SpeechAnalyzer` does its own endpointing, better than the VAD does, and feeding it disconnected
   utterances would cost accuracy and latency.
2. **Transcribe.** `SpeechAnalyzerTranscriber` streams audio into `SpeechTranscriber`, emitting
   speaker-tagged `TranscriptSegment`s as they finalize. Fully on-device once the locale's model is
   installed (§5) — no network call, no cloud fallback (there isn't one; see §6).
3. **Window.** `WikiMatchCoordinator` keeps a sliding window of the last N utterances (`windowSize`,
   2–6 depending on the `WikiSuggestionFrequency` setting).
4. **Match.** Each new segment re-runs `WikiMatcher`: build an L2-normalized TF-IDF query vector
   from the window, cosine-compare it against every document's pre-computed vector in `WikiIndex`.
5. **Trigger.** If the top score clears the confidence threshold (a `0...1` value, with Low/Medium/
   High presets in Settings → Behavior), `WikiMatchCoordinator` publishes a match — debounced so the
   same page doesn't re-fire every segment, and scored per-candidate rather than over the whole
   window, so an early strong entity can't permanently outrank the actual current topic.
6. **Render.** `OverlayView` (SwiftUI, hosted in the `OverlayPanel` `NSPanel`) observes the match and
   animates the card in: title, status, latest-update/summary, blocker, quick actions (Copy Status,
   Open Page, external links), plus the "Ask Wikily" field for grounded follow-up Q&A.

### 3.3 Concurrency model

Swift 6 strict concurrency throughout. `CallCaptureSession` is an `actor` so capture state is never
touched from two threads at once. `CallSession`, `AppSettings`, and the UI-facing controllers are
`@MainActor`. Long-running work (indexing a large wiki folder, installing the speech model) runs in
detached `Task`s and reports back to `@MainActor` state via `@Observable` properties SwiftUI
observes directly — no explicit event bus; `@Observable` + SwiftUI's own diffing does that job.

---

## 4. Core Components

| Capability | Where | Notes |
|---|---|---|
| System + mic audio capture, VAD | `Audio/{CallCaptureSession,SystemAudioTap,MicrophoneCapture,VoiceActivityDetector}.swift` | `SystemAudioTap` builds a CoreAudio aggregate device + process tap; verified working (mono, 48 kHz, clean teardown) against real hardware. |
| Floating macOS panel | `Overlay/OverlayPanel.swift` (`NSPanel` subclass) | `.nonactivatingPanel` (click doesn't steal focus from the call), `.floating` level, `.canJoinAllSpaces` + `.fullScreenAuxiliary` (stays over a full-screen Zoom call and follows Spaces), `becomesKeyOnlyIfNeeded` (the "Ask Wikily" field can still take real keyboard focus for typing). |
| Window positioning / dynamic height | `Overlay/OverlayLayout.swift`, `Overlay/OverlayWindowController.swift` | Pure-geometry layout logic kept separate from the window controller specifically so placement math is unit-testable without a screen. |
| App-wide menu bar | `AppMainMenu.swift` | Built in code, not a `.xib` — a regular (Dock-icon) app with no `NSApp.mainMenu` has literally no working ⌘C/⌘V/⌘A anywhere, including Settings text fields, since the Edit menu is what wires those into the responder chain. |
| Status-bar control surface | `Overlay/MenuBarController.swift` | The only control surface Wikily has beyond the menu bar — deliberately no global hotkeys, which would need Accessibility permission far broader than anything the product needs. |
| On-device speech-to-text | `Transcription/{SpeechAnalyzerTranscriber,SpeechModelInstaller,LiveTranscriber,AudioFileTranscriber}.swift` | Apple `Speech` framework. `SpeechModelInstaller` wraps `AssetInventory` for locale-model install/progress. |
| Wiki engine | `Wiki/{WikiScanner,MarkdownParser,Tokenizer,WikiIndex,WikiMatcher,WikiMatchCoordinator,WikiIndexCache}.swift` | Scan → parse (YAML frontmatter, headers, `#tags`, `[[wikilinks]]`) → tokenize → TF-IDF index → cosine match → confidence-gated, debounced trigger. |
| Grounded Q&A ("Ask Wikily") | `Chat/{AskSession,GroundedPrompt}.swift` | Quick actions ("What should I say?", "Recap," "Fact-check," "Follow-up questions") and a free-text field, both grounded in the matched page + live transcript. Output-capped two ways (`maximumResponseTokens` on the model call, `maximumAnswerCharacters` as a client-side backstop) after an early build spiraled into a runaway repeated-bullet-point answer on an empty transcript. |
| Model backends | `Models/{AppleFoundationModelService,LocalServerModelService,LanguageModelService,LocalServerDiscovery,ModelDiagnostics}.swift` | Apple's on-device Foundation Models framework, or an OpenAI-compatible local server (Ollama/LM Studio) auto-discovered by port probing — one `LanguageModelService` protocol, two backends. |
| Settings & persistence | `AppState/AppSettings.swift`, `Settings/*.swift` | `UserDefaults`-backed, namespaced keys (`settings.<area>.<name>`) so a non-sandboxed app's flat defaults domain doesn't collide with future features. Injectable `UserDefaults` suite so tests never touch the real user's prefs (`Wikily.app` is its own `TEST_HOST`; see `DefaultsIsolationTests`). |
| First-run onboarding | `Onboarding/{OnboardingView,OnboardingWindowController,OnboardingStep}.swift` | Presented on first launch, or Settings opens instead on every subsequent launch — `MenuBarController.presentStartupWindow()`. |
| Calendar sync + meeting reminders | `Calendar/*.swift`, `Settings/CalendarSettingsView.swift`, `Settings/NotificationPermission.swift` | Opt-in Google/Outlook OAuth (Authorization Code + PKCE via `ASWebAuthenticationSession`, no client secret), Keychain-backed tokens, a 60-second poll (`CalendarSyncCoordinator`) merging upcoming events, and a local `UNUserNotificationCenter` reminder one minute before any event with a detected Zoom/Meet/Teams/Webex join link (`MeetingReminderPlan`, `MeetingNotificationScheduler`). The one deliberate exception to §6's "no cloud" posture — see there and `docs/CALENDAR_INTEGRATION.md`. |

---

## 5. Local Speech Model

Covered in full in [`docs/LOCAL_TRANSCRIPTION.md`](./docs/LOCAL_TRANSCRIPTION.md) — summary: the
on-device model for the user's locale downloads once (Apple's own asset, via `AssetInventory`),
surfaced with a progress bar in both the Setup Assistant and the Model settings tab
(`Settings/SpeechModelState.swift` is the single observable both bind to, so they can't disagree).
After that one download, transcription needs no network at all.

---

## 6. Local-First, No Cloud Fallback

The product spec's local-first requirement is not a default-with-opt-out here — there is no cloud
speech path at all. Transcription is always `SpeechAnalyzer` on-device. Outside the initial model
download, the two places a network call happens are the **Q&A model** (local by default) and, as
of the calendar integration, **calendar sync** — and unlike the Q&A model, that one is never local,
by its nature:

| Concern | Behavior |
|---|---|
| Transcription | Always on-device (`SpeechAnalyzer`); no cloud STT exists in this codebase |
| Wiki matching | Always local (TF-IDF over a locally-indexed folder); no embeddings API call |
| Q&A model | Apple on-device Foundation Models by default, **or** a local server (Ollama/LM Studio) the user points at explicitly — both stay on the user's Mac or LAN. Nothing routes to a hosted LLM API. |
| Calendar sync | **Off by default, opt-in, and the one deliberate exception.** Only when the user connects a Google or Outlook account in Settings › Calendar does Wikily talk to Google's or Microsoft's own OAuth/Calendar APIs directly — to read event times, titles, and join links so it can remind the user a meeting is starting. Nothing about a call (audio, transcript, matched pages) is sent alongside that; the two subsystems don't share code. See `docs/CALENDAR_INTEGRATION.md`. |
| Persistence | Settings in `UserDefaults`, wiki index cache as local JSON. Transcript lives only in the in-memory sliding window — never written to disk. Calendar OAuth tokens are the one exception to "`UserDefaults` for everything" — they live in the Keychain (`CalendarTokenStoring`), not alongside ordinary preferences. |

**`match_log`** (local engagement telemetry, product spec §7) was scoped for the KPI but hasn't
been built — it would be a small local JSONL file if wanted, not the SQLite table the old fork plan
assumed.

---

## 7. Performance, Verified

| Metric | Target | Status |
|---|---|---|
| Transcript latency | text within ~2 s of utterance | Met — `SpeechAnalyzer` streams continuously; no batching delay |
| HUD fade-in | card visible within 1.5 s of the trigger utterance | Verified on a real recorded 4-part call: small talk correctly surfaced nothing, then three real matches at 100%/94%/97% confidence |
| Wiki indexing | fast re-scan on a real vault | `WikiIndexCache` makes re-scans incremental — only changed files (by content hash, not mtime) get re-parsed; a fixture-sized vault logs "reused N, parsed 0, pruned 0" on an unchanged re-scan |
| Match accuracy | resolves a specific project/entity query correctly, offline | Verified — proven equivalent to a reference TypeScript engine to 6 decimal places, and robust to real transcription noise (see §2) |
| App footprint | lean, no bundled ML runtime | No ONNX/embeddings runtime, no bundled model binary — the only large asset is the OS-managed speech model, which the OS itself stores once, shared with every app that uses `Speech` |

---

## 8. How the Build Got Here

Not a single milestone plan against a chosen stack (§5 of the old Tauri-fork spec) — the actual
sequence, phases 0–6 done, phase 7 remaining:

- **Phase 0** — hand-authored Xcode project, builds and signs.
- **Phase 1** — wiki engine (scanner, parser, tokenizer, TF-IDF index, matcher), proven equivalent
  to a reference implementation to 6 decimal places.
- **Phase 2** — CoreAudio process tap, aggregate device, device enumeration, VAD, WAV writer.
- **Phase 3** — `SpeechAnalyzer` streaming transcription, model installer.
- **Phase 4** — the overlay HUD.
- **Phase 5** — model services (two backends behind one protocol).
- **Phase 6** — unified settings, first-run onboarding, persistence, grounded Q&A ("Ask Wikily").
- **Phase 7 (remaining)** — delete the old Tauri/React source tree that's still sitting alongside
  this app in the repo, update CI/CD and this doc set, then merge `native-rewrite` to `master`.
  Tracked in `docs/NATIVE_REWRITE_ROADMAP.md`.

---

## 9. Security & Privacy

- **On-device by default, no exceptions for transcription:** call audio and transcript never leave
  the machine — there is no cloud transcription code path to accidentally hit.
- **Q&A model stays local or LAN-local:** on-device Foundation Models, or a local server the user
  explicitly points at (Ollama/LM Studio) — never a hosted API.
- **Minimal persistence:** transcripts live only in the in-memory sliding window. Settings and the
  wiki index cache persist; raw call content does not.
- **Filesystem scope:** the app reads only the user-selected wiki folder.
- **Permissions:** microphone and speech-recognition usage descriptions are declared in the app's
  Info.plist keys (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`); the
  system prompts on first use. Notification authorization (for meeting reminders) is requested the
  same way, lazily, the first time it's actually needed rather than at launch.
- **Calendar sync is opt-in and narrowly scoped:** off until the user connects an account; reads
  calendar metadata only (`calendar.readonly` / `Calendars.Read` — never write access); OAuth
  tokens live in the Keychain, not `UserDefaults`; disconnecting an account deletes its Keychain
  entry immediately. See §6 and `docs/CALENDAR_INTEGRATION.md`.

---

## 10. Open Questions & Risks

Superseded by the living list in
[`docs/NATIVE_REWRITE_ROADMAP.md`](./docs/NATIVE_REWRITE_ROADMAP.md) — that file is the source of
truth for what's unverified or still open (full-screen Zoom behavior live, the local-server model
backend against a real running server, HUD-vs-wireframe visual comparison, the Tauri deletion
itself, docs, and a real release/signing pipeline). Don't duplicate that list here; update it there.

---

## 11. Appendix

### 11.1 Key file index (citations)
- App entry / menu bar: `WikilyApp.swift`, `AppMainMenu.swift`
- Status item / control surface: `Overlay/MenuBarController.swift`
- Floating panel: `Overlay/{OverlayPanel,OverlayWindowController,OverlayLayout,OverlayView,OverlayTheme}.swift`
- Call orchestration: `AppState/CallSession.swift`
- Audio capture: `Audio/{CallCaptureSession,SystemAudioTap,MicrophoneCapture,VoiceActivityDetector,AudioChunk,CoreAudioSupport,AudioDeviceStore,WAVWriter,CaptureDiagnostics,CaptureError}.swift`
- Transcription: `Transcription/{SpeechAnalyzerTranscriber,SpeechModelInstaller,LiveTranscriber,AudioFileTranscriber,TranscriptSegment}.swift`
- Wiki engine: `Wiki/{WikiScanner,MarkdownParser,Tokenizer,StableHash,WikiDocument,WikiIndex,WikiIndexCache,WikiMatcher,WikiMatchCoordinator}.swift`
- Q&A: `Chat/{AskSession,GroundedPrompt}.swift`
- Model backends: `Models/{LanguageModelService,AppleFoundationModelService,LocalServerModelService,LocalServerDiscovery,ModelDiagnostics}.swift`
- Settings: `AppState/AppSettings.swift`, `Settings/*.swift`
- Onboarding: `Onboarding/*.swift`
- Calendar sync + meeting reminders: `Calendar/*.swift` (`CalendarAccountStore`,
  `CalendarSyncCoordinator`, `MeetingNotificationScheduler`, `GoogleCalendarClient`,
  `OutlookCalendarClient`, `CalendarTokenStore`, `OAuthBrowserSession`, `MeetingLinkExtractor`),
  `Settings/{CalendarSettingsView,NotificationPermission}.swift` — see
  `docs/CALENDAR_INTEGRATION.md`
- Tests: `WikilyTests/` (`xcodebuild test`; the 242-test/23-suite figure elsewhere in this doc
  predates the calendar suites added here and hasn't been re-counted)

### 11.2 Glossary
- **HUD / overlay** — the always-on-top floating `NSPanel` (`Overlay/OverlayPanel.swift`).
- **Sliding window** — the last few utterances used as the match query, sized by
  `WikiSuggestionFrequency`.
- **Confidence threshold** — the `0...1` cosine-similarity gate a match must clear to trigger a card.
- **Ask Wikily** — the grounded Q&A field on the HUD card, plus its quick-action shortcuts.
- **Local-first** — all processing on-device; there is no cloud path to opt into for transcription
  or matching, and the Q&A model defaults to on-device too.
- **Meeting reminder** — the local notification `MeetingNotificationScheduler` fires one minute
  before a connected calendar's meeting starts, for any event with a detected join link.
