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
  full test suite on `macos-latest`) and paused `.github/workflows/publish.yml`
  (was auto-publishing a release of the **old Tauri app** on every push to
  `master` — now `workflow_dispatch` only, so merging this branch can't
  accidentally trigger it). Neither has actually run in GitHub Actions yet —
  see "Verify CI actually works" below.

## Not ready to merge into `master` yet

The core reason: **`native-rewrite` is purely additive.** `git diff
master...native-rewrite` is 14,000+ insertions and zero deletions — the old
Tauri/TypeScript app (`src/`, `src-tauri/`, `package.json`, `dist/`, ...) is
still fully intact and untouched in this branch. Merging today wouldn't
complete the rewrite, it would just add a second app living next to the
first one.

## Next steps, roughly in order

1. **Verify CI actually works.** The `swift` job in `ci.yml` has never run in
   GitHub Actions — it was only exercised locally (`xcodebuild build`/`test`
   against Xcode 26.6, macOS 26.0 deployment target). Push a commit (or open
   a PR) and watch it. The most likely failure mode is Xcode-version mismatch
   on the runner image — the job comment explains how to pin one with
   `maxim-lobanov/setup-xcode`'s `xcode-version:` input if `latest-stable`
   doesn't resolve a usable SDK/destination.

2. **Do the hands-on verification pass.** These are real product-behavior
   questions, not something more unit tests would catch:
   - Overlay behavior against a real full-screen Zoom call, and following the
     user across Spaces/desktops — asserted as window flags in
     `OverlayPanelTests`, never watched live.
   - The local-server model backend (Ollama/LM Studio) against an actual
     running server — `--probe-models` exercises the wire format, but nobody
     has pointed it at a real server and read a real response.
   - The wireframe-fidelity HUD restyle (this session and the one before) —
     never compared side-by-side against the Claude Design mockup, only
     checked via `--overlay-preview` screenshots.

3. ~~**Look at the two build warnings.**~~ Done — clean build now has zero
   Swift compiler warnings. `CoreAudioSupport.swift`'s `AudioObject.array`
   switched from the implicit `&values` array-to-pointer conversion (which
   the compiler can't clear for a generic `T`, even though every real call
   site uses a trivial type) to the explicit `withUnsafeMutableBytes` API;
   verified against real hardware with `--probe-audio` afterward, not just
   by the warning disappearing. `OverlayView.swift`'s deprecated `Text + Text`
   concatenation became nested `Text` string interpolation, which preserves
   the same per-segment styling (semibold "Blocker: " label, regular-weight
   body).

4. **Phase 7: delete the Tauri app**, as its own clean commit — `src/`,
   `src-tauri/`, `package.json`, `package-lock.json`, `dist/`, `coverage/`,
   `vite.config.ts`, `vitest.config.ts`, `tsconfig*.json`, `components.json`,
   `.npmrc`, `.vscode/` if Tauri-specific. Cross-check `.gitignore` afterward
   — several entries (`node_modules`, `dist`, `coverage`) exist only for the
   Tauri app and can go too.

5. ~~**Update the stale docs.**~~ Done.
   - `README.md` — full rewrite. The old one wasn't even Wikily-specific: it
     was still describing the upstream **Pluely** product (GPL v3 branding,
     cross-platform Win/Linux, a license/monetization system, screenshot
     capture, a chat Dashboard — none of which Wikily has), with one sentence
     about Wikily awkwardly inserted. Now describes the actual native app,
     how to build/test it, and flags the repo's mid-transition state plainly.
   - `Tech Spec Wikily.md` — full rewrite. The old version specified an
     entire Tauri/Rust/React/SQLite implementation, file paths and all, that
     was never built. Replaced with the real architecture: component
     diagram, module table, and file citations against what's actually in
     `Wikily/Wikily/`.
   - `Product Spec Wikily.md` — lighter touch, deliberately. The persona/
     workflow/KPI/monetization thinking (§1, §2, §6–8) didn't change with the
     tech stack, so it's untouched. Only the sections describing *how* it's
     built (§1.3, §1.5, §3.1, §3.3, §4 — all the "Pluely fork" framing) got
     inline "superseded, see top note" markers pointing at the Tech Spec,
     rather than being rewritten in place — the Tech Spec is meant to be the
     one current, authoritative build reference.
   - `docs/LOCAL_TRANSCRIPTION.md` — full rewrite. The real story turned out
     much simpler than the whisper.cpp-sidecar plan this doc detailed: Apple's
     `Speech` framework downloads and manages its own on-device model, no
     bundling/signing pipeline needed at all.

6. **Decide what replaces `publish.yml`.** It's paused, not replaced. The
   native app needs its own release pipeline: `xcodebuild archive` +
   codesign with a Developer ID + notarization + stapling, on a tag push.
   There's a pinned note "macOS release signing setup" that suggests this was
   already being tracked separately — check there before starting from
   scratch.

7. **Merge to `master`**, once 4–6 are done and 2 has had a real pass.

## Two things flagged earlier, still undecided

- `match_log` local engagement telemetry (original spec §7 relevance KPI) —
  dropped when the SQLite layer went; would come back as a small local JSONL
  file instead if wanted.
- Nothing else outstanding from the Phase 6 notes.
