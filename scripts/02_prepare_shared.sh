#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[prepare_shared] Creating shared dir: $SHARED_DIR"
sudo mkdir -p "$SHARED_DIR"
sudo chown "${USER}:${USER}" "$SHARED_DIR"
echo "[prepare_shared] Done"


