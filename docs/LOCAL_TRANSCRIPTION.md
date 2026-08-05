# Local (on-device) transcription

> **This doc describes the native macOS app** (`Wikily/`, the `native-rewrite`
> branch). It previously described a `whisper.cpp` sidecar bundled into the
> old Tauri app — that plan was scaffolded but never shipped. The native
> rewrite replaced it with Apple's own on-device Speech framework, which
> turned out to need none of the bundling/signing machinery this doc used to
> walk through. See `docs/NATIVE_REWRITE_ROADMAP.md` for where the rewrite
> stands overall.

Wikily is **local-first**: it transcribes call audio entirely on-device with
Apple's `SpeechAnalyzer` / `SpeechTranscriber` APIs (the `Speech` framework),
so no audio or transcript ever leaves the machine. There is no cloud fallback
and no "opt in to send audio to a server" path — Wikily doesn't have a cloud
speech provider at all. That's a real product decision, not a current
limitation: transcript content and wiki content can be sensitive, and the
whole design assumes it never has to leave the Mac.

## How it works

- `Wikily/Wikily/Transcription/SpeechAnalyzerTranscriber.swift` streams
  VAD-gated audio chunks into `SpeechAnalyzer`/`SpeechTranscriber` and gets
  back live, speaker-tagged transcript segments — no external process, no
  sidecar binary, no network call once the model is installed.
- The on-device model for a given language has to be downloaded once before
  it can be used — `Wikily/Wikily/Transcription/SpeechModelInstaller.swift`
  wraps Apple's `AssetInventory` API for this: it resolves the best matching
  locale for the user's system language, reports whether that locale's model
  is `.notInstalled` / `.downloading(fraction:)` / `.installed`, and drives
  the download with live progress. This is the **one moment in Wikily's
  lifetime that needs the network** — after it completes, transcription works
  fully offline.
- `SpeechModelState` (`Wikily/Wikily/Settings/SpeechModelState.swift`) is the
  shared observable both the first-run Setup Assistant and the **Model**
  settings tab bind to, so they can never disagree about what state the model
  is in. Both show the same "Download Speech Model" button and progress bar.

## What a user actually does

Nothing beyond clicking a button. There's no terminal, no script, no
config file:

1. First launch: the Setup Assistant checks the model state. If it's not
   installed, it shows a **Download Speech Model** button with a progress
   bar.
2. That download is Apple's own asset — a locale-specific speech model
   distributed and updated by the OS, not something Wikily builds, hosts, or
   bundles. Once it finishes, `SpeechModelInstaller.State` reports
   `.installed`.
3. From then on, every call is transcribed fully on-device. Nothing here
   needs re-running unless the user changes their system language to one that
   needs a different model, which the Model settings tab surfaces the same
   way.

If a locale has no on-device model at all, `SpeechModelInstaller.state`
reports `.unsupported` and the UI says so plainly rather than silently
falling back to something else — there's nothing to fall back *to*.

## Verifying end-to-end

Two headless diagnostics exercise this without opening the app:

```bash
# Install (or confirm) the on-device model for the current locale.
Wikily --install-speech-model

# Re-transcribe an existing WAV file or a directory of them, printing the
# windowed match decision and the standalone top-3 candidates per utterance —
# useful for isolating whether a bug is in transcription or in the wiki
# matcher.
Wikily --transcribe <path> --vault <wiki-path>
```

For the real capture path, `Wikily --probe-speech` builds the full audio
pipeline (device capture → VAD → `SpeechAnalyzer`) against a live microphone
and prints what comes back — see `Wikily/Wikily/Audio/CaptureDiagnostics.swift`
for what it and the sibling `--probe-audio`/`--capture-diagnostics` flags do.
