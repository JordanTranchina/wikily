# Releasing a new version of Wikily

1. Decide the version number, e.g. `1.2.0`.
2. In a terminal, in this repo:
   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```
3. Wait for the "release" workflow to finish — check
   <https://github.com/JordanTranchina/wikily/actions>.
4. Done. The new build is at
   <https://github.com/JordanTranchina/wikily/releases/latest>,
   and everyone with an existing copy of Wikily will be offered the update
   automatically the next time Wikily checks (in-app, via Settings → General
   → "Automatically check for updates", or immediately via the app menu's
   "Check for Updates…").

If the Actions run fails, nothing was published — old releases are
untouched, and the version tag can be deleted and re-pushed once the
problem's fixed:

```bash
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0
```

## What the workflow actually does

`.github/workflows/release.yml` triggers on any tag matching `v*`. It:

1. Archives the app with `xcodebuild archive`, ad-hoc signed (no Apple
   Developer Program enrollment needed — see
   [`NATIVE_REWRITE_ROADMAP.md`](NATIVE_REWRITE_ROADMAP.md) for why).
2. Zips it and publishes a GitHub Release with that zip attached.
3. Regenerates `appcast.xml` (the file Sparkle checks for "is there a
   newer version") and commits it straight to `master` — the one
   automated, bot-authored commit this process makes.

## One-time setup this depends on

Already done, documented here in case the signing key is ever lost and
needs regenerating: Wikily is signed for updates with a Sparkle EdDSA key
pair. The private half lives only in the `SPARKLE_PRIVATE_KEY` GitHub
Actions repo secret (Settings → Secrets and variables → Actions) and in
the local macOS Keychain of whoever ran `generate_keys`. The public half is
baked into the app itself (`SUPublicEDKey` in `Wikily/SparkleInfo.plist`). If the
private key is ever lost, no existing install can verify a future update
signed with a new key — a fresh key pair would mean every existing user
has to manually download and right-click → Open the next release once,
same as a first install.
