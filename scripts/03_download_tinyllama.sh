#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
else
  echo "[download_model] ERROR: Unable to locate $COMMON_SETUP" >&2
  exit 1
fi

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


