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

# Also stage the model into resources/ so a distribution build ships it inside
# the app (so end users don't have to run setup-whisper.sh). The overlay's
# `resources/whisper/*.bin` glob picks up whatever model is here, and
# transcribe.rs resolves it from the app's resource dir at runtime.
RES_DIR="$ROOT/src-tauri/resources/whisper"
APP_ID="com.srikanthnani.pluely"
case "$(uname -s)" in
  Darwin) MODEL_SRC_DIR="$HOME/Library/Application Support/$APP_ID/whisper" ;;
  Linux)  MODEL_SRC_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID/whisper" ;;
  *)      MODEL_SRC_DIR="" ;;
esac

MODEL_SRC=""
for name in ggml-base.en.bin ggml-small.en.bin ggml-tiny.en.bin; do
  if [ -n "$MODEL_SRC_DIR" ] && [ -f "$MODEL_SRC_DIR/$name" ]; then
    MODEL_SRC="$MODEL_SRC_DIR/$name"; break
  fi
  if [ -f "$WORKDIR/models/$name" ]; then
    MODEL_SRC="$WORKDIR/models/$name"; break
  fi
done

if [ -n "$MODEL_SRC" ]; then
  mkdir -p "$RES_DIR"
  cp "$MODEL_SRC" "$RES_DIR/$(basename "$MODEL_SRC")"
  echo "Staged model:   $RES_DIR/$(basename "$MODEL_SRC")"
else
  echo "Note: no model found to bundle for distribution (run setup-whisper.sh)."
  echo "      A local build still works via the app-data model + sidecar."
fi

echo ""
echo "Now build WITH the whisper overlay so the sidecar (+ any staged model) is bundled:"
echo "  npm run tauri build -- --config src-tauri/tauri.whisper.conf.json"
echo "…or run a dev build:"
echo "  npm run tauri dev -- --config src-tauri/tauri.whisper.conf.json"
