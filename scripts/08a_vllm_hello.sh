#!/usr/bin/env bash
set -euo pipefail

# Simple "hello" completion against vLLM OpenAI-compatible API
# Usage:
#   VLLM_BASE_URL=http://127.0.0.1:8000 ./08a_vllm_hello.sh
# or rely on VLLM_HOST/VLLM_PORT, or defaults to 127.0.0.1:8000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
fi

BASE_URL="${VLLM_BASE_URL:-}"
if [[ -z "${BASE_URL}" ]]; then
  HOST="${VLLM_TEST_HOST:-${VLLM_HOST_IP:-${VLLM_HOST:-127.0.0.1}}}"
  PORT="${VLLM_PORT:-8000}"
  if [[ "$HOST" == "0.0.0.0" ]]; then
    HOST="127.0.0.1"
  fi
  BASE_URL="http://${HOST}:${PORT}"
fi

JQ_AVAILABLE=1
if ! command -v jq >/dev/null 2>&1; then
  JQ_AVAILABLE=0
fi

echo "[vllm-hello] Using base URL: ${BASE_URL}"

# Discover a model if not provided
MODEL="${MODEL:-}"
if [[ -z "${MODEL}" ]]; then
  if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
    MODEL=$(curl -sS "${BASE_URL}/v1/models" | jq -r '.data[0].id // empty') || true
  fi
fi
if [[ -z "${MODEL}" ]]; then
  # Fallback if discovery fails; vLLM usually accepts any string and maps to served model
  MODEL="default"
fi

echo "[vllm-hello] Using model: ${MODEL}"

REQ=$(cat <<'JSON'
{
  "model": "__MODEL__",
  "prompt": "Say hello in one sentence.",
  "max_tokens": 64,
  "temperature": 0.7
}
JSON
)
REQ=${REQ/__MODEL__/${MODEL}}

RESP=$(curl -sS -X POST "${BASE_URL}/v1/completions" \
  -H "Content-Type: application/json" \
  -d "${REQ}")

if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
  echo "${RESP}" | jq '.choices[0].text // .'
else
  echo "${RESP}"
fi


