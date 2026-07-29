#!/usr/bin/env bash
# Fast sanity check: does the frontend still compile and build?
# Does NOT launch the app — see build-and-run.sh for that.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "==> Switching to design/wikily-wireframes"
git checkout design/wikily-wireframes

echo "==> Installing dependencies"
npm install

echo "==> Building frontend (typecheck + vite build)"
npm run build

echo "==> Build OK"
