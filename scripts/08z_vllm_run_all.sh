#!/usr/bin/env bash
set -euo pipefail

# Runs the vLLM test scripts in sequence.
# Usage:
#   VLLM_BASE_URL=http://127.0.0.1:8000 ./08z_vllm_run_all.sh
# Optional: MODEL env var to use a specific served model.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
fi

echo "[vllm-runner] Starting vLLM tests..."

echo "\n===== HELLO (completions) ====="
"${SCRIPT_DIR}/08a_vllm_hello.sh"

echo "\n===== HAIKU (chat) ====="
"${SCRIPT_DIR}/08b_vllm_haiku.sh"

echo "\n===== MATH (chat) ====="
"${SCRIPT_DIR}/08c_vllm_math.sh"

echo "\n[vllm-runner] All tests completed."


