# Wikily

A local-first macOS overlay that proactively surfaces the right page from your own markdown
wiki while you're on a call — no cloud, no manual search, nothing leaves your Mac.

> **Status:** the native macOS app described below is being built on the `native-rewrite` branch
> and is not yet merged to `master`. This repository currently also contains an earlier,
> unrelated Tauri/React prototype (`src/`, `src-tauri/`) that predates this direction and is
> being removed — see [`docs/NATIVE_REWRITE_ROADMAP.md`](docs/NATIVE_REWRITE_ROADMAP.md) for
> where that stands. If you're reading this from `master`, some of what's below may not be there
> yet; check that branch.

## What it does

You're on a Zoom call. A client asks a question you'd normally dig for in Notion, Obsidian, or a
pile of docs. Wikily is already listening (on-device, nothing recorded to disk beyond an
in-memory sliding window) and matching what's being said against a folder of markdown files you
point it at. When it finds a strong match, a small card fades in over the call — title, status,
the latest update, a blocker if there is one, and a quick way to copy it or open the source page.
No hotkey, no typing a search query mid-call.

If nothing's matched yet, or you want to go further, "Ask Wikily" is a grounded Q&A field on the
same card — "what should I say," "recap the call," "fact-check that," or your own question —
answered from whatever page matched plus the live transcript.

## Why local-first, all the way down

- **Transcription is always on-device.** Apple's `SpeechAnalyzer` does the work; there's no cloud
  speech API in this codebase to opt into or accidentally hit.
- **Matching is always local.** A TF-IDF index built from your own wiki folder — no embeddings
  API, no data leaving the machine to compute a match.
- **The Q&A model stays local or LAN-local.** Apple's on-device Foundation Models by default, or a
  local server (Ollama, LM Studio) you point it at explicitly. Nothing routes to a hosted LLM.
- **Nothing about a call is written to disk.** The transcript lives only in an in-memory sliding
  window for as long as the call runs.

See [`Tech Spec Wikily.md`](Tech%20Spec%20Wikily.md) for the real architecture and file-by-file
citations, and [`Product Spec Wikily.md`](Product%20Spec%20Wikily.md) for the product thinking
(personas, workflow, KPIs) behind it.

## Features

- **Proactive HUD** — a floating card that fades in over your call (stays above full-screen Zoom,
  follows you across Spaces) when your wiki has something relevant, without you asking for it.
- **Ask Wikily** — grounded Q&A on the same card: quick actions ("What should I say?",
  "Follow-up questions", "Fact-check", "Recap") and a free-text field, both answered from the
  matched page and the live transcript, never invented from nothing.
- **On-device transcription** — Apple's `Speech` framework does the work after a one-time,
  OS-managed model download; see [`docs/LOCAL_TRANSCRIPTION.md`](docs/LOCAL_TRANSCRIPTION.md).
- **Your own wiki, your own format** — point it at any folder of markdown files. Frontmatter,
  headers, `#tags`, and `[[wikilinks]]` are parsed for structure; no particular tool or schema is
  required.
- **A real Settings app** — General (login item, permissions), Knowledge Base (wiki folder,
  index stats, re-scan), Model (on-device or local-server Q&A backend), Behavior (match
  sensitivity, overlay transparency and text size), Audio (input/output device selection).
- **First-run onboarding**, so pointing Wikily at a wiki folder and picking a Q&A model doesn't
  require reading this file first.
- **In-app updates** — Sparkle checks for new releases and installs them with no manual
  re-download; see [Download](#download) above for the one-time first-install step.

## Download

Grab the latest build from [Releases](https://github.com/JordanTranchina/wikily/releases/latest).

**First launch only:** macOS will warn that Wikily "cannot be verified" — this is
expected (Wikily isn't notarized by Apple; see
[`docs/NATIVE_REWRITE_ROADMAP.md`](docs/NATIVE_REWRITE_ROADMAP.md) for why). Right-click
(or Control-click) `Wikily.app` and choose **Open**, then confirm in the dialog that
appears. You only need to do this once — every update after that installs automatically
in the background with no warning. See [`docs/RELEASING.md`](docs/RELEASING.md) if
you're cutting a new release rather than downloading one.

## Building it

Requires Xcode (the project targets a recent macOS SDK — check
`Wikily.xcodeproj`'s deployment target if your Xcode is older).

```bash
git clone https://github.com/JordanTranchina/wikily.git
cd wikily
git checkout native-rewrite   # see the Status note above
open Wikily/Wikily.xcodeproj
```

Build and run from Xcode (⌘R), or from the command line:

```bash
cd Wikily
xcodebuild -project Wikily.xcodeproj -scheme Wikily -destination 'platform=macOS' build
```

### Running the tests

```bash
cd Wikily
xcodebuild -project Wikily.xcodeproj -scheme Wikily -destination 'platform=macOS' test
```

242 tests across 23 suites, all logic-level — wiki engine, audio capture, transcription,
matching, chat, settings, overlay geometry.

### Headless diagnostics

A few pieces of Wikily can't be meaningfully unit-tested (the CoreAudio object graph, real
speech, real matching against a real vault) and instead have command-line probes — see
`Wikily/Wikily/Audio/CaptureDiagnostics.swift` and
[`docs/LOCAL_TRANSCRIPTION.md`](docs/LOCAL_TRANSCRIPTION.md) for what's available
(`--probe-audio`, `--probe-speech`, `--install-speech-model`, `--transcribe`, and more).

## Repository layout

```
Wikily/                  the native macOS app (Xcode project, Swift/AppKit/SwiftUI)
  Wikily/                app source
  WikilyTests/           the test target
docs/                    developer docs (local transcription, the native-rewrite roadmap)
Product Spec Wikily.md   product spec — personas, workflow, KPIs, monetization thinking
Tech Spec Wikily.md      technical spec — architecture, file citations, performance
src/, src-tauri/         legacy Tauri/React app, being removed — see the roadmap doc
```

## Contributing

This is a young, actively-changing project — check
[`docs/NATIVE_REWRITE_ROADMAP.md`](docs/NATIVE_REWRITE_ROADMAP.md) for what's currently in flight
before starting anything large, so you're not racing an in-progress rewrite of the same area.
Bug-fix PRs with a clear description of the bug and the fix are welcome. For anything bigger —
new features, architectural changes — open an issue first to talk it through.

## License

[GNU General Public License v3.0](LICENSE).
