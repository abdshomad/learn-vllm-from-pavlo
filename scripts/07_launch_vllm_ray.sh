#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine NODE_IP and VLLM_HOST_IP BEFORE sourcing common.sh
# to avoid VLLM_HOST_IP defaulting to 0.0.0.0
NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

# Set VLLM_HOST_IP to actual IP before sourcing to prevent default 0.0.0.0
export VLLM_HOST_IP="${VLLM_HOST_IP:-${NODE_IP}}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[launch_vllm_ray] Starting vLLM (Ray backend) on ${VLLM_HOST}:${VLLM_PORT}"
echo "[launch_vllm_ray] Node IP: ${NODE_IP}"
echo "[launch_vllm_ray] VLLM_HOST_IP: ${VLLM_HOST_IP}"
echo "[launch_vllm_ray] Model: ${MODEL_DIR}"
echo "[launch_vllm_ray] Tensor Parallel Size: ${TENSOR_PARALLEL_SIZE}"
echo "[launch_vllm_ray] Ray backend: distributed"

uv run python -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_DIR" \
  --host "$VLLM_HOST" --port "$VLLM_PORT" \
  --distributed-executor-backend ray \
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" &

VLLM_PID=$!
echo "[launch_vllm_ray] vLLM started with PID: ${VLLM_PID}"

echo "[launch_vllm_ray] Waiting for vLLM to initialize..."
sleep 5

# Check if vLLM is still running
if ! kill -0 $VLLM_PID 2>/dev/null; then
  echo "[launch_vllm_ray] ERROR: vLLM process died" >&2
  exit 1
fi

echo "[launch_vllm_ray] vLLM is running"
echo ""
echo "[launch_vllm_ray] Access URLs:"
echo "[launch_vllm_ray] - vLLM API: http://${NODE_IP}:${VLLM_PORT}"
echo "[launch_vllm_ray] - vLLM Docs: http://${NODE_IP}:${VLLM_PORT}/docs"
echo "[launch_vllm_ray] - Ray Dashboard: http://${NODE_IP}:8265"
echo "[launch_vllm_ray] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[launch_vllm_ray] - Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "[launch_vllm_ray] Done"
echo ""
echo "[launch_vllm_ray] Press Ctrl+C to stop vLLM"

# Wait for the process
wait $VLLM_PID


