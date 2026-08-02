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

6. **Decided (2026-08-02), not yet built: replace `publish.yml` with a free
   distribution path — no Apple Developer Program enrollment for now.**
   Talked through as a product decision, not just an engineering one — full
   reasoning below, since the "why" matters if this gets revisited.

   - **Audience:** not just Jordan anymore — plan is to share a GitHub link
     with other people to download.
   - **Update experience wanted:** the app should notice a new version exists
     and prompt in-app, not "check a webpage occasionally."
   - **The $99/year Apple Developer Program fee is not being paid right
     now.** That fee is specifically the price of *notarization* — the thing
     that stops a downloaded app from triggering macOS's "Apple cannot
     verify this app is free of malware" Gatekeeper warning. There is no
     free workaround for that specific warning; it's an Apple platform rule,
     not something to architect around. Decided it's not worth it yet.
   - **What's still buildable for free, and what isn't:**
     - ✅ **[Sparkle](https://sparkle-project.org/)** for the in-app
       "Update available" check/download/install flow. Sparkle itself is
       free/open-source and needs no Apple account — its own update
       integrity check uses a separate, self-managed EdDSA key pair, not
       Apple's notarization.
     - ✅ **GitHub Releases** as the free hosting/distribution point —
       ad-hoc/self-signed builds (`codesign --sign -`, what local Xcode runs
       already use), no Developer ID needed to produce or host them.
     - ⚠️ **The tradeoff this leaves in place:** every new version Sparkle
       delivers is *still an unnotarized download* the first time its new
       binary runs, so it **still triggers the Gatekeeper warning once per
       update**, same as first install. Sparkle solves "does the app know
       and offer to update," not "does macOS trust it." The mitigation is
       procedural, not technical: document right-click → "Open" (which
       surfaces an "Open Anyway" button in the dialog itself, rather than
       sending someone into System Settings) prominently wherever the
       download link lives — this needs to be real, visible instructions by
       the time anyone outside Jordan is asked to download it, not a detail
       left to word-of-mouth. Worth noting this workaround has been getting
       quietly harder across recent macOS releases, so it's a mitigation,
       not a permanent guarantee.
     - **Revisit paying the fee if:** the Gatekeeper warning becomes a real
       adoption blocker for new downloaders, or distribution ever wants to
       move to TestFlight (internal testing without a public link — cleaner
       for a small known group) or the Mac App Store — both still require
       the same paid enrollment, so there's no cheaper tier that unlocks
       just one of them.
   - **Concrete build steps, not yet started:**
     1. Add Sparkle as a Swift Package dependency to `Wikily.xcodeproj`.
     2. Generate a Sparkle EdDSA key pair (one-time, free, self-managed —
        `generate_keys` tool ships with Sparkle).
     3. Wire Sparkle's update-checker into the app (menu item + automatic
        background check) and add its required Info.plist keys
        (`SUFeedURL`, `SUPublicEDKey`).
     4. New GitHub Actions workflow (replacing the paused `publish.yml`):
        on a version tag push, `xcodebuild archive` → export a `.app` →
        zip/dmg it → generate/update the Sparkle `appcast.xml` → publish
        both to a new GitHub Release.
     5. Add clear, visible "first time opening this? Right-click → Open"
        instructions to the README's download section and/or the release
        notes template.

7. **Merge to `master`**, once 4–6 are done and 2 has had a real pass.

## Two things flagged earlier, still undecided

- `match_log` local engagement telemetry (original spec §7 relevance KPI) —
  dropped when the SQLite layer went; would come back as a small local JSONL
  file instead if wanted.
- Nothing else outstanding from the Phase 6 notes.
