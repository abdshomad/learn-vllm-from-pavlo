#!/usr/bin/env bash
set -euo pipefail

# Generate a short haiku using chat/completions
# Usage:
#   VLLM_BASE_URL=http://127.0.0.1:8000 ./08b_vllm_haiku.sh
# Optional: MODEL env var to force a specific model name

BASE_URL="${VLLM_BASE_URL:-}"
if [[ -z "${BASE_URL}" ]]; then
  HOST="${VLLM_HOST:-127.0.0.1}"
  PORT="${VLLM_PORT:-8000}"
  BASE_URL="http://${HOST}:${PORT}"
fi

JQ_AVAILABLE=1
if ! command -v jq >/dev/null 2>&1; then
  JQ_AVAILABLE=0
fi

echo "[vllm-haiku] Using base URL: ${BASE_URL}"

MODEL="${MODEL:-}"
if [[ -z "${MODEL}" ]]; then
  if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
    MODEL=$(curl -sS "${BASE_URL}/v1/models" | jq -r '.data[0].id // empty') || true
  fi
fi
if [[ -z "${MODEL}" ]]; then
  MODEL="default"
fi

echo "[vllm-haiku] Using model: ${MODEL}"

REQ=$(cat <<'JSON'
{
  "model": "__MODEL__",
  "messages": [
    {"role": "system", "content": "You are a concise creative writing assistant."},
    {"role": "user", "content": "Write a 3-line haiku about GPUs and parallel computation."}
  ],
  "max_tokens": 80,
  "temperature": 0.8
}
JSON
)
REQ=${REQ/__MODEL__/${MODEL}}

RESP=$(curl -sS -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${REQ}")

if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
  echo "${RESP}" | jq -r '.choices[0].message.content // .'
else
  echo "${RESP}"
fi


