#!/usr/bin/env bash
# Builds and launches the app in dev mode (hot-reload window).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "==> Switching to design/wikily-wireframes"
git checkout design/wikily-wireframes

echo "==> Installing dependencies"
npm install

echo "==> Building & launching app (npm run tauri dev)"
# Stream tauri dev's output as-is, but inject an unambiguous banner the
# moment the Rust side finishes compiling and launches — otherwise a clean
# build is easy to miss in the middle of cargo warnings/HMR log spam.
# Cargo's colored output puts ANSI escapes *between* words (e.g.
# "Finished\x1b[0m `dev`"), so strip escapes before matching, not after.
npm run tauri dev 2>&1 | awk '
  {
    line = $0
    gsub(/\033\[[0-9;]*[a-zA-Z]/, "", line)
    print line
    if (line ~ /Finished .dev. profile/) {
      print "\n=== ✅ App built and running cleanly ===\n"
      fflush()
    }
    if (line ~ /^error(\[|:)/) {
      print "\n=== ❌ Build failed — see error above ===\n"
      fflush()
    }
  }
'
