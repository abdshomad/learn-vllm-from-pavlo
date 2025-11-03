#!/usr/bin/env bash
set -euo pipefail

# Math/Reasoning test using chat/completions
# Usage:
#   VLLM_BASE_URL=http://127.0.0.1:8000 ./08c_vllm_math.sh
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

echo "[vllm-math] Using base URL: ${BASE_URL}"

MODEL="${MODEL:-}"
if [[ -z "${MODEL}" ]]; then
  if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
    MODEL=$(curl -sS "${BASE_URL}/v1/models" | jq -r '.data[0].id // empty') || true
  fi
fi
if [[ -z "${MODEL}" ]]; then
  MODEL="default"
fi

echo "[vllm-math] Using model: ${MODEL}"

# A simple but non-trivial math word problem
PROBLEM="If a train travels 120 kilometers in 1.5 hours, then continues for 2 hours at a speed that is 20% slower, how far does it travel in total? Show brief steps and give the final numeric answer in kilometers."

# Properly escape the problem for JSON
PROBLEM_JSON=$(echo "$PROBLEM" | jq -Rs . 2>/dev/null || echo "\"${PROBLEM//\"/\\\"}\"")

REQ=$(cat <<JSON
{
  "model": "__MODEL__",
  "messages": [
    {"role": "system", "content": "You are a careful math tutor. Be concise and accurate."},
    {"role": "user", "content": __PROBLEM__}
  ],
  "max_tokens": 256,
  "temperature": 0.2
}
JSON
)
REQ=${REQ/__MODEL__/${MODEL}}
REQ=${REQ/__PROBLEM__/${PROBLEM_JSON}}

RESP=$(curl -sS -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${REQ}")

if [[ ${JQ_AVAILABLE} -eq 1 ]]; then
  echo "${RESP}" | jq -r '.choices[0].message.content // .'
else
  echo "${RESP}"
fi


