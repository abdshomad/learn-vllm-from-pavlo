#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

export VLLM_HOST_IP="${VLLM_HOST_IP}"

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

echo "[launch_vllm_single] Starting vLLM (single node) on ${VLLM_HOST}:${VLLM_PORT}"
echo "[launch_vllm_single] Node IP: ${NODE_IP}"
echo "[launch_vllm_single] Model: ${MODEL_DIR}"
echo "[launch_vllm_single] Tensor Parallel Size: ${TENSOR_PARALLEL_SIZE}"

uv run python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --host "$VLLM_HOST" --port "$VLLM_PORT" \
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" &

VLLM_PID=$!
echo "[launch_vllm_single] vLLM started with PID: ${VLLM_PID}"

echo "[launch_vllm_single] Waiting for vLLM to initialize..."
sleep 5

# Check if vLLM is still running
if ! kill -0 $VLLM_PID 2>/dev/null; then
  echo "[launch_vllm_single] ERROR: vLLM process died" >&2
  exit 1
fi

echo "[launch_vllm_single] vLLM is running"
echo ""
echo "[launch_vllm_single] Access URLs:"
echo "[launch_vllm_single] - vLLM API: http://${NODE_IP}:${VLLM_PORT}"
echo "[launch_vllm_single] - vLLM Docs: http://${NODE_IP}:${VLLM_PORT}/docs"
echo "[launch_vllm_single] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[launch_vllm_single] - Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "[launch_vllm_single] Done"
echo ""
echo "[launch_vllm_single] Press Ctrl+C to stop vLLM"

# Wait for the process
wait $VLLM_PID


