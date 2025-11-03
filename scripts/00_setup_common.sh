#!/usr/bin/env bash
set -euo pipefail

# Determine repo root and script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults (override via environment variables before calling scripts)
: "${PYTHON_VERSION:=3.13}"
: "${VENV_DIR:=$REPO_ROOT/.venv}"
: "${SHARED_DIR:=/mnt/shared/cluster-llm}"
: "${MODEL_NAME:=TinyLlama-1.1B-Chat-v1.0}"
: "${MODEL_REPO:=https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
: "${MODEL_DIR:=$SHARED_DIR/$MODEL_NAME}"
: "${VLLM_PORT:=8000}"
: "${VLLM_HOST:=0.0.0.0}"
: "${TENSOR_PARALLEL_SIZE:=2}"
: "${RAY_PORT:=6379}"

# Optional network binding for vLLM multi-NIC
: "${VLLM_HOST_IP:=${VLLM_HOST}}"

# Helper: activate venv if present
activate_venv() {
  if [[ -d "$VENV_DIR" ]]; then
    # shellcheck source=/dev/null
    source "$VENV_DIR/bin/activate"
  fi
}

# Helper: detect primary IP if not provided
primary_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}


