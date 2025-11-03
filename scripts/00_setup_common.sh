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
: "${VLLM_HOST:=0.0.0.0}"
: "${TENSOR_PARALLEL_SIZE:=2}"
: "${RAY_PORT:=6379}"
: "${PROMETHEUS_PORT:=9090}"
: "${GRAFANA_PORT:=3000}"

# Optional network binding for vLLM multi-NIC
: "${VLLM_HOST_IP:=${VLLM_HOST}}"

# Grafana credentials (change after first login)
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASS:=admin}"

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

# Helper: find next available port starting from a given port
find_available_port() {
  local start_port="${1:-8000}"
  local port="$start_port"
  
  while command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$port" 2>/dev/null; do
    ((port++))
    # Safety: don't scan forever
    if [[ $port -gt $((start_port + 100)) ]]; then
      echo "$start_port" >&2
      return 1
    fi
  done
  
  echo "$port"
}

# Auto-find available VLLM port if not explicitly set
if [[ -z "${VLLM_PORT:-}" ]]; then
  VLLM_PORT=$(find_available_port 8000)
fi


