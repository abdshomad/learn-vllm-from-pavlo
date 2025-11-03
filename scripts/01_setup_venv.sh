#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[setup_venv] Installing uv (if needed)"
if ! command -v uv >/dev/null 2>&1; then
  curl -Ls https://astral.sh/uv/install.sh | sh
  # Ensure current shell can find uv; users may need to re-source their profile
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "[setup_venv] Creating venv at $VENV_DIR with Python $PYTHON_VERSION"
mkdir -p "$REPO_ROOT"
cd "$REPO_ROOT"
uv venv "$VENV_DIR" -p "$PYTHON_VERSION"

echo "[setup_venv] Activating venv and installing packages"
activate_venv

uv pip install --upgrade pip
uv pip install "ray[default]" vllm huggingface_hub git-lfs

echo "[setup_venv] Done"


