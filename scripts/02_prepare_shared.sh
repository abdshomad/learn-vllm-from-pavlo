#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
else
  echo "[prepare_shared] ERROR: Unable to locate $COMMON_SETUP" >&2
  exit 1
fi

echo "[prepare_shared] Creating shared dir: $SHARED_DIR"

# Try simplest approach first: create without sudo
if mkdir -p "$SHARED_DIR" 2>/dev/null; then
  # Verify the directory is writable by the current user
  if [[ -w "$SHARED_DIR" ]]; then
    echo "[prepare_shared] Created directory successfully and verified writable"
  else
    echo "[prepare_shared] WARNING: Directory created but not writable by current user"
    # Try to fix with passwordless sudo
    if sudo -n true 2>/dev/null; then
      echo "[prepare_shared] Using passwordless sudo to fix permissions"
      sudo chown "${USER}:${USER}" "$SHARED_DIR"
    else
      echo "[prepare_shared] ERROR: Directory exists but is not writable"
      echo "[prepare_shared] Suggestion: Run 'sudo chown $USER:$USER $SHARED_DIR' manually"
      exit 1
    fi
  fi
else
  # If that fails, try with passwordless sudo
  if sudo -n true 2>/dev/null; then
    echo "[prepare_shared] Using passwordless sudo to create directory"
    sudo mkdir -p "$SHARED_DIR"
    sudo chown "${USER}:${USER}" "$SHARED_DIR"
  else
    echo "[prepare_shared] ERROR: Cannot create $SHARED_DIR"
    echo "[prepare_shared] Parent directory may not exist or may require sudo privileges"
    echo "[prepare_shared] Suggestion: Run 'sudo mkdir -p $SHARED_DIR && sudo chown $USER:$USER $SHARED_DIR' manually"
    exit 1
  fi
fi

echo "[prepare_shared] Done"


