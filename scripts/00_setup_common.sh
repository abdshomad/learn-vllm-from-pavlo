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

# Ensure Ray uses a writable temporary directory
: "${RAY_TMPDIR:=/tmp/ray-${USER:-$(id -u)}}"
if [[ -d "$RAY_TMPDIR" && ! -w "$RAY_TMPDIR" ]]; then
  ALT_RAY_TMPDIR="$REPO_ROOT/.ray_tmp"
  mkdir -p "$ALT_RAY_TMPDIR"
  RAY_TMPDIR="$ALT_RAY_TMPDIR"
fi
mkdir -p "$RAY_TMPDIR"
export RAY_TMPDIR

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

# Helper: ensure uv is in PATH
ensure_uv_in_path() {
  # Check if uv is already available
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi
  
  # Try common installation locations
  local uv_paths=(
    "$HOME/.local/bin/uv"
    "/root/.local/bin/uv"
    "/usr/local/bin/uv"
  )
  
  for uv_path in "${uv_paths[@]}"; do
    if [[ -x "$uv_path" ]]; then
      export PATH="$(dirname "$uv_path"):$PATH"
      return 0
    fi
  done
  
  # If still not found, try to add common directories to PATH
  local common_dirs=(
    "$HOME/.local/bin"
    "/root/.local/bin"
    "/usr/local/bin"
  )
  
  for dir in "${common_dirs[@]}"; do
    if [[ -d "$dir" ]] && [[ -x "$dir/uv" ]]; then
      export PATH="$dir:$PATH"
      return 0
    fi
  done
  
  return 1
}

# Ensure uv is available
ensure_uv_in_path || {
  echo "WARNING: uv not found in PATH. Some scripts may fail." >&2
  echo "Please ensure uv is installed and in your PATH." >&2
}


