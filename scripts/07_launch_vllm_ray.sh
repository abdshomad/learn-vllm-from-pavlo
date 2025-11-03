#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

export VLLM_HOST_IP="${VLLM_HOST_IP}"

echo "[launch_vllm_ray] Starting vLLM (Ray backend) on ${VLLM_HOST}:${VLLM_PORT}"
uv run python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --host "$VLLM_HOST" --port "$VLLM_PORT" \
  --distributed-executor-backend ray \
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE"


