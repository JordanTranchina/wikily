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
  accidentally trigger it). Verified working in GitHub Actions —
  [run #13](https://github.com/JordanTranchina/wikily/actions/runs/30764485999)
  passed, including the new `swift` job.

## Not ready to merge into `master` yet

The core reason: **`native-rewrite` is purely additive.** `git diff
master...native-rewrite` is 14,000+ insertions and zero deletions — the old
Tauri/TypeScript app (`src/`, `src-tauri/`, `package.json`, `dist/`, ...) is
still fully intact and untouched in this branch. Merging today wouldn't
complete the rewrite, it would just add a second app living next to the
first one.

## Next steps, roughly in order

1. **Do the hands-on verification pass.** These are real product-behavior
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

2. **Phase 7: delete the Tauri app**, as its own clean commit — `src/`,
   `src-tauri/`, `package.json`, `package-lock.json`, `dist/`, `coverage/`,
   `vite.config.ts`, `vitest.config.ts`, `tsconfig*.json`, `components.json`,
   `.npmrc`, `.vscode/` if Tauri-specific. Cross-check `.gitignore` afterward
   — several entries (`node_modules`, `dist`, `coverage`) exist only for the
   Tauri app and can go too.

3. **Decided (2026-08-02), not yet built: replace `publish.yml` with a free
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
       already use), no Developer ID needed to produce or host them. May
       need Hardened Runtime's "Library Validation" turned off for an
       ad-hoc-signed build to load Sparkle at all — a build setting, not a
       fee.
     - **The tradeoff is smaller than first written here — corrected
       2026-08-02.** Originally this said every Sparkle-delivered update
       would re-trigger the Gatekeeper warning. That's wrong. Gatekeeper's
       warning is gated specifically on the `com.apple.quarantine` extended
       attribute, which only quarantine-aware downloaders (browsers, Mail,
       etc.) apply — and **Sparkle strips that attribute from the updates it
       downloads and installs**, well-documented enough that it's a known
       security consideration for update-channel compromise, not a fringe
       claim (see sources below). Net effect: **only the first manual
       download+install** (from GitHub Releases, via a browser) needs the
       right-click → "Open" workaround. Every update after that, delivered
       through Sparkle, installs and relaunches with no repeat warning —
       the actual "smooth in-app update" experience that was wanted,
       achievable without paying anything. The workaround still needs to be
       real, visible instructions wherever the download link lives (it's
       every *new* user's first-install experience, permanently, not a
       one-time launch problem) — that part of the original reasoning
       stands.
       Sources: [Sparkle docs](https://sparkle-project.org/documentation/)
       (EdDSA verification is independent of Apple code-signing; ad-hoc
       signed apps can receive updates), and
       [lapcatsoftware.com's notarization analysis](https://lapcatsoftware.com/articles/notarization.html)
       (quarantine-stripping behavior and its security implications, corroborated by SpecterOps' write-up of it as a real attack vector).
     - **Revisit paying the fee if:** the first-install Gatekeeper warning
       becomes a real adoption blocker for new downloaders, or distribution
       ever wants to move to TestFlight (internal testing without a public
       link — cleaner for a small known group) or the Mac App Store — both
       still require the same paid enrollment, so there's no cheaper tier
       that unlocks just one of them.
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

4. **Merge to `master`**, once 2–3 are done and 1 has had a real pass.

## Two things flagged earlier, still undecided

- `match_log` local engagement telemetry (original spec §7 relevance KPI) —
  dropped when the SQLite layer went; would come back as a small local JSONL
  file instead if wanted.
- Nothing else outstanding from the Phase 6 notes.
