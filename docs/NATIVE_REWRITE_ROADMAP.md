# Native rewrite: merge readiness and next steps

Status as of **2026-08-02**, `native-rewrite` branch. Written down so a future
session (or a future you) can pick this up without re-deriving it.

## Where things stand

- Phases 0–6 done: wiki engine, CoreAudio capture, on-device speech, the
  overlay HUD, model services, settings/onboarding/persistence, Ask Wikily.
  242 tests passing across 23 suites (`xcodebuild test`).
- This session: full AppKit menu bar with Quit in both the app menu and the
  Window menu, a fix for a real SwiftUI/AppKit bug that silently stripped the
  main menu down to nothing when the overlay's text field took focus,
  most-recent-build-wins process handling in Debug, a user-adjustable overlay
  text size setting, and Settings opening automatically on launch.
- CI: added a `swift` job to `.github/workflows/ci.yml` (builds + runs the
  full test suite on `macos-latest`). Verified working in GitHub Actions —
  [run #13](https://github.com/JordanTranchina/wikily/actions/runs/30764485999)
  passed, including the new `swift` job.
- Sparkle auto-updates: built and verified locally (commit `d8bdff6`, **not
  yet pushed to `origin`**) — see item 2 below for what's left. Replaces the
  old `.github/workflows/publish.yml`, which used to auto-publish a release
  of the **old Tauri app** on every push to `master`.

## Not ready to merge into `master` yet

The core reason: **`native-rewrite` is purely additive.** `git diff
master...native-rewrite` is 14,000+ insertions and zero deletions — the old
Tauri/TypeScript app (`src/`, `src-tauri/`, `package.json`, `dist/`, ...) is
still fully intact and untouched in this branch. Merging today wouldn't
complete the rewrite, it would just add a second app living next to the
first one.

## Next steps, roughly in order

1. **Push the Sparkle commit, then prove the release pipeline actually
   works end-to-end.** Sparkle auto-updates are built and locally verified
   (see [`docs/RELEASING.md`](RELEASING.md) for the mechanics; the full
   product/engineering reasoning for going with Sparkle + ad-hoc signing
   instead of paying for Apple Developer Program enrollment is preserved
   below) but nothing has touched `origin` yet:
   - Push commit `d8bdff6` to `origin/native-rewrite`.
   - Push a throwaway test tag (e.g. `v0.0.1-test`) and watch
     `.github/workflows/release.yml` run — confirms the ad-hoc archive,
     GitHub Release, and `appcast.xml` → `master` commit all actually work
     in CI, not just locally.
   - Cut the first real tagged release (e.g. `v0.1.0`), install it via the
     README's right-click → Open flow, then cut a second release and confirm
     the installed copy updates itself through Sparkle with **no** repeat
     Gatekeeper warning — the specific claim the whole decision rests on.

   <details>
   <summary>Why Sparkle + ad-hoc signing instead of paying for notarization (decided 2026-08-02)</summary>

   - **Audience:** not just Jordan anymore — plan is to share a GitHub link
     with other people to download.
   - **Update experience wanted:** the app should notice a new version exists
     and prompt in-app, not "check a webpage occasionally."
   - **The $99/year Apple Developer Program fee is not being paid right
     now.** That fee is specifically the price of *notarization* — the thing
     that stops a downloaded app from triggering macOS's "Apple cannot
     verify this app is free of malware" Gatekeeper warning. There is no
     free workaround for that specific warning; it's an Apple platform rule,
     not something to architect around.
   - **[Sparkle](https://sparkle-project.org/)** is free/open-source and
     needs no Apple account — its own update integrity check uses a
     separate, self-managed EdDSA key pair, not Apple's notarization.
     **GitHub Releases** is the free hosting point for ad-hoc/self-signed
     builds.
   - **Only the first manual download+install needs the right-click → "Open"
     workaround.** Gatekeeper's warning is gated on the `com.apple.quarantine`
     extended attribute, which only quarantine-aware downloaders (browsers,
     Mail, etc.) apply — and Sparkle strips that attribute from the updates
     it installs. Every update after the first, delivered through Sparkle,
     installs with no repeat warning.
     Sources: [Sparkle docs](https://sparkle-project.org/documentation/),
     [lapcatsoftware.com's notarization analysis](https://lapcatsoftware.com/articles/notarization.html).
   - **Revisit paying the fee if:** the first-install Gatekeeper warning
     becomes a real adoption blocker for new downloaders, or distribution
     ever wants to move to TestFlight or the Mac App Store — both still
     require the same paid enrollment.

   </details>

2. **Do the hands-on verification pass.** These are real product-behavior
   questions, not something more unit tests would catch. Written up as
   Given/When/Then acceptance criteria below so each one has a clear
   pass/fail, not just "seems fine."

   #### A. Overlay vs. full-screen Zoom and Spaces

   Setup: `Wikily --overlay-preview [vault-path]` puts the HUD on screen
   against the bundled sample vault (or a real one) without needing a live
   call — pair it with an actual Zoom meeting in full-screen for these.

   - **A1 — Overlay stays above a full-screen Zoom call.**
     Given Wikily is listening and a wiki match is showing on the HUD,
     when the active Zoom window is switched to full-screen (green-button
     or the in-call full-screen toggle),
     then the HUD is still visible, drawn above the Zoom window, not hidden
     behind it or pushed to another Space by macOS's own full-screen
     window handling.
   - **A2 — Overlay follows across Spaces.**
     Given the HUD is visible on the current Space,
     when the user swipes to a different Space (trackpad swipe or
     Mission Control),
     then the HUD is still visible on the new Space in the same screen
     position, not left behind on the original one.
   - **A3 — Overlay survives Zoom's own full-screen Space.**
     Given a Zoom call is running in full-screen (which macOS gives its own
     dedicated Space),
     when the user is on that dedicated full-screen Space,
     then the HUD is visible there too, not only on the regular desktop
     Spaces.
   - **A4 — Overlay doesn't steal focus from the call.**
     Given a full-screen Zoom call is running and the HUD fades in with a
     new match,
     when nothing has been clicked in the HUD,
     then Zoom keeps keyboard/mouse focus — typing or clicking still goes
     to the call, not the HUD — and the HUD only takes focus once its Ask
     field is clicked.
   - **A5 — Ask field works without dropping the call to the background.**
     Given the HUD's Ask field is clicked and focused,
     when a question is typed and submitted,
     then the Zoom call keeps running uninterrupted behind it (audio
     doesn't glitch, the call isn't minimized or hidden).

   #### B. Local-server model backend against a real server

   Setup: `Wikily --probe-models` exercises the wire format against
   whatever's listening on 11434 (Ollama) / 1234 (LM Studio) / 8080
   (llama-server) — run it once with the server up to sanity-check the
   request/response shape before the full app-level check below.

   - **B1 — Ollama round trip.**
     Given Ollama is running locally with a model pulled (e.g. `ollama run
     llama3`), and Wikily's Model settings are pointed at the local-server
     backend on port 11434,
     when a question is asked via Ask Wikily on a matched page,
     then a real, coherent answer streams back into the HUD, grounded in
     the matched page's content (not a generic/hallucinated response).
   - **B2 — LM Studio round trip.**
     Given LM Studio is running locally with a model loaded on port 1234,
     and Wikily's Model settings are pointed at it,
     when the same Ask Wikily flow is used,
     then the answer streams back correctly, same as B1 — confirming the
     backend isn't accidentally Ollama-specific.
   - **B3 — Server picked up automatically when already running.**
     Given a local server was already running before Wikily launched,
     when Settings → Model is opened,
     then Wikily's local-server discovery finds it without needing a
     manual restart or re-scan (matches what `LocalServerDiscoveryTests`
     asserts in isolation — this confirms it holds against a real server).
   - **B4 — Clear failure when the server drops mid-call.**
     Given a question is asked against a local server that's running,
     when the server process is killed partway through the response,
     then the HUD shows a clear "couldn't reach the model" state rather
     than hanging indefinitely or showing a silent empty answer.

   #### C. HUD visual fidelity vs. the Claude Design wireframes

   Setup: open the `Wikily Wireframes.dc.html` Claude Design project (the
   WikiCard HUD screen) side by side with `Wikily --overlay-preview`, at
   the default overlay-transparency and font-size settings.

   - **C1 — Layout and information hierarchy match.**
     Given the wireframe's expanded WikiCard state,
     when the built HUD is showing a matched page in its expanded state,
     then the title, status, latest update, blocker line, and action row
     appear in the same order and rough proportions as the wireframe.
   - **C2 — Brand color and match badge match.**
     Given the wireframe's accent blue (`#3457d5`) and match-badge amber
     (`#e0a83f`),
     when the built HUD is compared at the same zoom level,
     then `OverlayTheme.accent`/`OverlayTheme.matchBadge` read as the same
     colors on screen, not a system-blue or a re-tinted approximation.
   - **C3 — Collapsed pill vs. expanded card transition matches.**
     Given the wireframe shows a collapsed pill state and an expanded card
     state as distinct designs,
     when the HUD is toggled between collapsed and expanded (via its own
     collapse control),
     then both states individually match their wireframe counterparts, not
     just the expanded one.
   - **C4 — Translucency reads correctly in both light and dark mode.**
     Given `OverlayMaterial` maps the Behavior-settings transparency slider
     to a native `Material` rather than the wireframe's literal CSS
     rgba/blur values,
     when the same overlay-transparency setting is viewed in both System
     Settings' light and dark appearance,
     then the HUD reads as "the same product" in both — appropriately
     vibrant/translucent, not washed out or illegibly dark in either mode.
   - **C5 — Font-size setting scales proportionally, not just the title.**
     Given `AppSettings.overlayFontSize` is changed in Behavior settings
     (11–18pt),
     when the HUD is viewed at the smallest and largest settings,
     then every label scales together relative to the 12pt reference
     (`OverlayTheme.referenceFontSize`) — status, quick actions, and chat
     text grow with the title, nothing stays a fixed size while everything
     else grows.

3. **Phase 7: delete the Tauri app**, as its own clean commit — `src/`,
   `src-tauri/`, `package.json`, `package-lock.json`, `dist/`, `coverage/`,
   `vite.config.ts`, `vitest.config.ts`, `tsconfig*.json`, `components.json`,
   `.npmrc`, `.vscode/` if Tauri-specific. Cross-check `.gitignore` afterward
   — several entries (`node_modules`, `dist`, `coverage`) exist only for the
   Tauri app and can go too.

4. **Merge to `master`**, once 1–3 are done.

## Two things flagged earlier, still undecided

- `match_log` local engagement telemetry (original spec §7 relevance KPI) —
  dropped when the SQLite layer went; would come back as a small local JSONL
  file instead if wanted.
- Nothing else outstanding from the Phase 6 notes.
