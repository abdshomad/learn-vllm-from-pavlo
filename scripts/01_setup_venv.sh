#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
else
  echo "[setup_venv] ERROR: Unable to locate $COMMON_SETUP" >&2
  exit 1
fi

echo "[setup_venv] Installing uv (if needed)"
if ! command -v uv >/dev/null 2>&1; then
  curl -Ls https://astral.sh/uv/install.sh | sh
  # Ensure current shell can find uv; check both user and root locations
  export PATH="$HOME/.local/bin:/root/.local/bin:$PATH"
  # Verify uv is now available
  if ! command -v uv >/dev/null 2>&1; then
    echo "[setup_venv] WARNING: uv was installed but not found in PATH" >&2
    echo "[setup_venv] Please ensure ~/.local/bin or /root/.local/bin is in your PATH" >&2
  fi
fi

echo "[setup_venv] Checking if venv already exists at $VENV_DIR"
mkdir -p "$REPO_ROOT"
cd "$REPO_ROOT"

if [[ -d "$VENV_DIR" ]]; then
  echo "[setup_venv] Virtual environment already exists at $VENV_DIR"
  echo "[setup_venv] Activating existing venv and verifying packages"
  activate_venv
  
  # Check if critical packages are installed
  if uv pip list | grep -q -E "(ray|vllm)"; then
    echo "[setup_venv] Packages appear to be installed. Skipping reinstall."
    echo "[setup_venv] Done"
    exit 0
  else
    echo "[setup_venv] Packages missing. Recreating venv..."
    rm -rf "$VENV_DIR"
  fi
fi

echo "[setup_venv] Creating venv at $VENV_DIR with Python $PYTHON_VERSION"
uv venv "$VENV_DIR" -p "$PYTHON_VERSION"

echo "[setup_venv] Activating venv and installing packages"
activate_venv

uv pip install --upgrade pip
uv pip install "ray[default]" vllm huggingface_hub git-lfs

echo "[setup_venv] Done"


