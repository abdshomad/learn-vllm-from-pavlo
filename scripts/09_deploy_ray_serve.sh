#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

# Ray Serve configuration
SERVE_HOST="${SERVE_HOST:-0.0.0.0}"
SERVE_PORT="${SERVE_PORT:-8001}"

echo "[deploy_ray_serve] Deploying Ray Serve application..."
echo "[deploy_ray_serve] Node IP: ${NODE_IP}"
echo "[deploy_ray_serve] Serve Host: ${SERVE_HOST}"
echo "[deploy_ray_serve] Serve Port: ${SERVE_PORT}"

# Check if Ray is running
if ! uv run python -m ray.scripts.scripts status >/dev/null 2>&1; then
  echo "[deploy_ray_serve] ERROR: Ray cluster is not running" >&2
  echo "[deploy_ray_serve] Please start Ray first with: bash scripts/04_start_ray_head.sh" >&2
  exit 1
fi

echo "[deploy_ray_serve] Ray cluster is running"

# Deploy the Serve application
echo "[deploy_ray_serve] Deploying application from ${REPO_ROOT}/serve_app.py"
echo "[deploy_ray_serve] Model: ${MODEL_DIR}"
echo "[deploy_ray_serve] Tensor Parallel Size: ${TENSOR_PARALLEL_SIZE}"

# By default, disable TinyLlama inside Serve to avoid GPU contention with the
# standalone vLLM server started by earlier scripts. Users can override by
# exporting SERVE_ENABLE_TINYLLAMA=1 before running this script.
SERVE_ENABLE_TINYLLAMA="${SERVE_ENABLE_TINYLLAMA:-0}"
echo "[deploy_ray_serve] SERVE_ENABLE_TINYLLAMA: ${SERVE_ENABLE_TINYLLAMA}"

if [[ "$SERVE_ENABLE_TINYLLAMA" != "0" ]]; then
  SINGLE_VLLM_PID_FILE="${REPO_ROOT}/.vllm_single_pid"
  if [[ -f "$SINGLE_VLLM_PID_FILE" ]]; then
    SINGLE_VLLM_PID="$(cat "$SINGLE_VLLM_PID_FILE" 2>/dev/null || true)"
    if [[ -n "${SINGLE_VLLM_PID}" ]] && kill -0 "$SINGLE_VLLM_PID" 2>/dev/null; then
      echo "[deploy_ray_serve] Detected standalone vLLM process (PID ${SINGLE_VLLM_PID}). Stopping it to free GPUs for Ray Serve..."
      if kill "$SINGLE_VLLM_PID" 2>/dev/null; then
        wait "$SINGLE_VLLM_PID" 2>/dev/null || true
        echo "[deploy_ray_serve] Standalone vLLM process stopped."
        rm -f "$SINGLE_VLLM_PID_FILE"
      else
        echo "[deploy_ray_serve] ⚠ Unable to terminate standalone vLLM process automatically." >&2
        echo "[deploy_ray_serve]    Please run 'bash scripts/99_shutdown_all.sh' and retry, or set SERVE_ENABLE_TINYLLAMA=0." >&2
        exit 1
      fi
    fi
  fi
fi

# Use the deployment script
cd "$REPO_ROOT"
SERVE_HOST="$SERVE_HOST" SERVE_PORT="$SERVE_PORT" MODEL_DIR="$MODEL_DIR" TENSOR_PARALLEL_SIZE="$TENSOR_PARALLEL_SIZE" SERVE_ENABLE_TINYLLAMA="$SERVE_ENABLE_TINYLLAMA" uv run python deploy_serve.py

echo ""
echo "[deploy_ray_serve] Ray Serve application deployed!"
echo "[deploy_ray_serve] Access URLs:"
echo "[deploy_ray_serve] - Ray Dashboard: http://${NODE_IP}:8265"
echo "[deploy_ray_serve] - Ray Serve (echo): http://${NODE_IP}:${SERVE_PORT}/echo"
echo "[deploy_ray_serve] - Ray Serve (calc): http://${NODE_IP}:${SERVE_PORT}/calc"
echo "[deploy_ray_serve] - Ray Serve (TinyLlama LLM): http://${NODE_IP}:${SERVE_PORT}/llm"
echo ""
echo "[deploy_ray_serve] Test with:"
echo "[deploy_ray_serve]   curl -X POST http://${NODE_IP}:${SERVE_PORT}/echo -H 'Content-Type: application/json' -d '{\"message\": \"Hello Ray Serve!\"}'"
echo "[deploy_ray_serve]   curl -X POST http://${NODE_IP}:${SERVE_PORT}/calc -H 'Content-Type: application/json' -d '{\"operation\": \"add\", \"a\": 10, \"b\": 5}'"
echo "[deploy_ray_serve]   curl -X POST http://${NODE_IP}:${SERVE_PORT}/llm -H 'Content-Type: application/json' -d '{\"prompt\": \"Hello, how are you?\", \"max_tokens\": 50}'"
echo "[deploy_ray_serve] Done"

