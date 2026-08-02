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
   questions, not something more unit tests would catch:
   - Overlay behavior against a real full-screen Zoom call, and following the
     user across Spaces/desktops — asserted as window flags in
     `OverlayPanelTests`, never watched live.
   - The local-server model backend (Ollama/LM Studio) against an actual
     running server — `--probe-models` exercises the wire format, but nobody
     has pointed it at a real server and read a real response.
   - The wireframe-fidelity HUD restyle — never compared side-by-side
     against the Claude Design mockup, only checked via `--overlay-preview`
     screenshots.

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
