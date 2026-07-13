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

1. **Bundle the sidecar.** Produce `whisper-cli` for each release target
   (`aarch64-apple-darwin`, `x86_64-apple-darwin`, and Windows/Linux if desired)
   named with Tauri's target-triple suffix, place them under
   `src-tauri/binaries/`, and add:
   ```jsonc
   // src-tauri/tauri.conf.json → bundle
   "externalBin": ["binaries/whisper-cli"]
   ```
   Add a "fetch/build whisper-cli" step to `.github/workflows/publish.yml`
   before `tauri-action` so releases can find the binaries.
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

## Verifying end-to-end

Local transcription can only be exercised on a real desktop build (the audio
capture + float-panel stack is macOS-first). After `setup-whisper.sh`:

```bash
npm run tauri dev
```

Start a capture, speak, and confirm speaker text appears and a matching wiki
card fades in. On a machine with no model installed and no cloud provider, the
app should surface the "finish local setup" hint instead of erroring out.
