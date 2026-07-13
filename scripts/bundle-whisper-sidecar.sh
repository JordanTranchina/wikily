#!/usr/bin/env bash
#
# Stage the whisper.cpp CLI as a Tauri sidecar so `tauri build`/`tauri dev` can
# bundle it into the app (Tech Spec §5.4). Run this AFTER scripts/setup-whisper.sh,
# on the same platform you're building for (macOS for a Mac release).
#
# Tauri names sidecars `<name>-<target-triple>`, and our overlay config
# (src-tauri/tauri.whisper.conf.json) declares the sidecar as `binaries/whisper-cli`.
# So this copies the built CLI to src-tauri/binaries/whisper-cli-<target-triple>.
set -euo pipefail

WORKDIR="${WIKILY_WHISPER_BUILD_DIR:-$HOME/.cache/wikily/whisper.cpp}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT/src-tauri/binaries"

# The Rust host target triple (e.g. aarch64-apple-darwin).
TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
if [ -z "$TRIPLE" ]; then
  echo "Could not determine the Rust host target triple (is rustc installed?)." >&2
  exit 1
fi

# Locate the CLI built by setup-whisper.sh (cmake build dir first, then the
# legacy `main` binary of older whisper.cpp checkouts).
BIN="$(find "$WORKDIR/build" -name whisper-cli -type f 2>/dev/null | head -n1 || true)"
if [ -z "${BIN:-}" ] && [ -x "$WORKDIR/main" ]; then
  BIN="$WORKDIR/main"
fi
if [ -z "${BIN:-}" ] || [ ! -x "$BIN" ]; then
  echo "whisper-cli not found under $WORKDIR." >&2
  echo "Run scripts/setup-whisper.sh first to build whisper.cpp." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/whisper-cli-$TRIPLE"
cp "$BIN" "$DEST"
chmod +x "$DEST"

echo "Staged sidecar: $DEST"
echo ""
echo "Now build WITH the whisper overlay so the sidecar is bundled:"
echo "  npm run tauri build -- --config src-tauri/tauri.whisper.conf.json"
echo "…or run a dev build:"
echo "  npm run tauri dev -- --config src-tauri/tauri.whisper.conf.json"
