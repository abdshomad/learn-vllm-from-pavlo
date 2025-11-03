#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[download_model] Target: $MODEL_DIR"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"

if [[ -d "$MODEL_DIR" && -f "$MODEL_DIR/config.json" ]]; then
  echo "[download_model] Model already present at $MODEL_DIR"
  exit 0
fi

echo "[download_model] Ensuring git-lfs is installed"
git lfs install

if [[ ! -d "$MODEL_NAME" ]]; then
  echo "[download_model] Cloning $MODEL_REPO"
  git clone "$MODEL_REPO" "$MODEL_NAME"
fi

# Optional: cleanup .git to save space
if [[ -d "$MODEL_NAME/.git" ]]; then
  echo "[download_model] Removing .git directory to save space"
  rm -rf "$MODEL_NAME/.git"
fi

echo "[download_model] Done"


