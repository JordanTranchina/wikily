# Local (on-device) transcription

Wikily is **local-first**: by default it transcribes call audio on-device with
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) so that no audio or
transcript ever leaves the machine (Tech Spec §4.2 / §5.4 / §9). Cloud speech
providers are a strictly opt-in fallback.

This doc covers how to enable local transcription today, and the remaining work
to ship it fully bundled.

## How it works

- `useSystemAudio` reads the transcription mode from settings
  (`WIKILY_TRANSCRIPTION_MODE`, default `local`). In **On-device** mode each
  VAD-gated WAV utterance is sent to the Rust command
  `transcribe_local` (`src-tauri/src/transcribe.rs`), which runs the
  whisper.cpp `whisper-cli` sidecar and returns text.
- If no local model/binary is installed, `transcribe_local` returns a typed
  `LOCAL_TRANSCRIPTION_UNAVAILABLE` error. The frontend then falls back to the
  configured **cloud** speech provider — but only if you've explicitly set one
  up (§6). Otherwise it prompts you to finish local setup. Nothing crashes.

`transcribe_local` looks for a model in this order:

1. `WIKILY_WHISPER_MODEL` — an explicit path (handy for development).
2. `<app_data_dir>/whisper/ggml-*.en.bin` — the conventional drop-in location,
   where `app_data_dir` is:
   - macOS: `~/Library/Application Support/com.srikanthnani.pluely/whisper/`
   - Linux: `~/.local/share/com.srikanthnani.pluely/whisper/`

Recommended models for streaming latency: `base.en` (default) or `small.en`,
quantized.

## Quick start (dev)

```bash
scripts/setup-whisper.sh            # builds whisper.cpp + fetches ggml-base.en.bin
# or: scripts/setup-whisper.sh small.en
```

The script builds `whisper-cli` and installs the model into the app-data
location above. Then, in Wikily → **Wiki Engine → Privacy & Transcription**,
make sure **On-device transcription** is enabled.

For the CLI binary, until sidecar bundling lands (below) either:

- point the app at a bundled sidecar named `whisper-cli`, or
- run a dev build with `whisper-cli` available to the shell.

## Remaining work to fully bundle (macOS release)

These steps require a macOS build machine and are intentionally **not** wired
into `tauri.conf.json` yet, because committing an `externalBin` entry without
the binaries present would break `tauri build` on every platform.

1. **Bundle the sidecar.** This is now staged as an **opt-in overlay** so the
   default build never references a binary that isn't there:
   - `src-tauri/tauri.whisper.conf.json` declares
     `bundle.externalBin: ["binaries/whisper-cli"]`.
   - `scripts/bundle-whisper-sidecar.sh` copies the CLI built by
     `setup-whisper.sh` to `src-tauri/binaries/whisper-cli-<target-triple>`
     (the naming Tauri expects). The binaries dir is git-ignored.
   You build *with* the overlay to get a bundled app (see **Building a
   whisper-bundled app** below). For CI releases, add a "build whisper-cli"
   step to `.github/workflows/publish.yml` for each target and pass
   `--config src-tauri/tauri.whisper.conf.json` to `tauri-action` (`args:`).
2. **Ship a model.** Either bundle a quantized `ggml-*.en.bin` as a Tauri
   `resources` entry and copy it into `app_data_dir/whisper/` on first run, or
   download-on-first-run with a progress UI.
3. **Code-sign + notarize.** `.github/workflows/publish.yml` now passes the
   Apple signing/notarization env vars to `tauri-action`, so all that's left is
   to add the repo secrets — until then the build stays unsigned (users see
   "Allow Anyway") but keeps succeeding. Add these repository secrets:
   - `APPLE_CERTIFICATE` — base64 of your "Developer ID Application" `.p12`
   - `APPLE_CERTIFICATE_PASSWORD` — password for that `.p12`
   - `APPLE_SIGNING_IDENTITY` — e.g. `Developer ID Application: Name (TEAMID)`
   - `APPLE_ID` — Apple ID email used for notarization
   - `APPLE_PASSWORD` — an app-specific password for that Apple ID
   - `APPLE_TEAM_ID` — your 10-character Apple Developer Team ID

   (Or swap the last three for the App Store Connect API key trio
   `APPLE_API_KEY` / `APPLE_API_ISSUER` / `APPLE_API_KEY_PATH`.) Once the
   sidecar is bundled (step 1), it is included in the signed payload
   automatically. Verify the notarized `.app`/`.dmg` on a Mac with
   `spctl -a -vvv <path>` and `xcrun stapler validate <path>`.

## Building a whisper-bundled app (at your Mac)

Once you're on macOS (14+ Apple Silicon recommended), produce an app with
whisper.cpp bundled in — three commands:

```bash
# 1. Build whisper.cpp + install a model into the app-data dir.
scripts/setup-whisper.sh            # or: scripts/setup-whisper.sh small.en

# 2. Stage the CLI as a Tauri sidecar (copies it to
#    src-tauri/binaries/whisper-cli-<target-triple>).
scripts/bundle-whisper-sidecar.sh

# 3a. Run it in dev, WITH the overlay so the sidecar is bundled:
npm run tauri dev -- --config src-tauri/tauri.whisper.conf.json

# 3b. …or produce a distributable build:
npm run tauri build -- --config src-tauri/tauri.whisper.conf.json
```

Then, in **Wiki Engine → Privacy & Transcription**, make sure **On-device
transcription** is on. `transcribe_local` calls the bundled `whisper-cli`
sidecar and reads the model from the app-data dir that step 1 populated.

Notes:
- **Model in a shipped app.** Step 1 installs the model into *your* machine's
  app-data dir, so a locally built app finds it. To ship the model to other
  users, also add the `ggml-*.en.bin` as a `bundle.resources` entry in the
  overlay and copy it into `app_data_dir/whisper/` on first run (or download it
  on first run with a progress UI).
- **Signing.** For a signed/notarized build, combine the overlay with the Apple
  secrets from step 3 of "Remaining work" — the bundled sidecar is signed as
  part of the app payload automatically.

## Verifying end-to-end

Local transcription can only be exercised on a real desktop build (the audio
capture + float-panel stack is macOS-first). `transcribe_local` invokes the
whisper.cpp **sidecar**, which Tauri resolves only from a bundled binary — so
to test on-device transcription you must run with the overlay (the
"Building a whisper-bundled app" steps above), not a plain `npm run tauri dev`.

Without the overlay/sidecar, `transcribe_local` returns
`LOCAL_TRANSCRIPTION_UNAVAILABLE` and the app falls back to your configured
cloud provider (or shows the "finish local setup" hint if none is set) — that
graceful-degradation path is worth confirming too. With the overlay: start a
capture, speak, and confirm speaker text appears and a matching wiki card fades
in.
