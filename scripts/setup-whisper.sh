#!/usr/bin/env bash
#
# Wikily local transcription setup (Tech Spec §5.4).
#
# Builds the whisper.cpp CLI and downloads a quantized English model into the
# location `transcribe_local` looks for, so on-device ("local") transcription
# works without any cloud provider. Everything stays on the machine (§4.2).
#
# Usage:
#   scripts/setup-whisper.sh [model]
#     model: tiny.en | base.en (default) | small.en
#
# After running, set the transcription mode to "On-device" in Wikily's
# Wiki Engine settings. See docs/LOCAL_TRANSCRIPTION.md for details.
set -euo pipefail

MODEL="${1:-base.en}"
WORKDIR="${WIKILY_WHISPER_BUILD_DIR:-$HOME/.cache/wikily/whisper.cpp}"

# Resolve the per-user app-data dir that the Tauri app reads models from.
# Mirrors tauri's app_data_dir() for the bundle identifier.
APP_ID="com.srikanthnani.pluely"
case "$(uname -s)" in
  Darwin) APP_DATA="$HOME/Library/Application Support/$APP_ID" ;;
  Linux)  APP_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID" ;;
  *)      echo "Unsupported OS for this helper. See docs/LOCAL_TRANSCRIPTION.md." >&2; exit 1 ;;
esac
MODEL_DIR="$APP_DATA/whisper"

echo "==> whisper.cpp build dir: $WORKDIR"
echo "==> model install dir:     $MODEL_DIR"
echo "==> model:                 ggml-$MODEL.bin"

# 1. Clone + build whisper.cpp (provides the `whisper-cli` binary).
if [ ! -d "$WORKDIR/.git" ]; then
  git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$WORKDIR"
fi
( cd "$WORKDIR" && git pull --ff-only || true )

echo "==> Building whisper.cpp (this can take a few minutes)…"
if command -v cmake >/dev/null 2>&1; then
  cmake -B "$WORKDIR/build" -S "$WORKDIR" -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$WORKDIR/build" --config Release -j --target whisper-cli >/dev/null
  BIN="$(find "$WORKDIR/build" -name whisper-cli -type f | head -n1)"
else
  make -C "$WORKDIR" -j
  BIN="$WORKDIR/main"  # older whisper.cpp names the CLI `main`
fi

# 2. Download the model.
mkdir -p "$MODEL_DIR"
bash "$WORKDIR/models/download-ggml-model.sh" "$MODEL"
cp "$WORKDIR/models/ggml-$MODEL.bin" "$MODEL_DIR/ggml-$MODEL.bin"

echo ""
echo "Done."
echo "  Model installed: $MODEL_DIR/ggml-$MODEL.bin"
echo "  whisper-cli:     ${BIN:-<not found>}"
echo ""
echo "To let the app find the CLI without full sidecar bundling, either:"
echo "  • export WIKILY_WHISPER_MODEL=\"$MODEL_DIR/ggml-$MODEL.bin\", and"
echo "  • bundle '$BIN' as the 'whisper-cli' Tauri sidecar (see docs), or run a"
echo "    dev build with it on PATH."
