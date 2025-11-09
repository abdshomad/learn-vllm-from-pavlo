#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
else
  echo "[launch_vllm_single] ERROR: Unable to locate $COMMON_SETUP" >&2
  exit 1
fi

export VLLM_HOST_IP="${VLLM_HOST_IP}"

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

echo "[launch_vllm_single] Starting vLLM (single node) on ${VLLM_HOST}:${VLLM_PORT}"
echo "[launch_vllm_single] Node IP: ${NODE_IP}"
echo "[launch_vllm_single] Model: ${MODEL_DIR}"
echo "[launch_vllm_single] Tensor Parallel Size: ${TENSOR_PARALLEL_SIZE}"

# Persist selected VLLM port for downstream scripts
VLLM_PORT_FILE="$REPO_ROOT/.cache/run_all/vllm_port"
mkdir -p "$(dirname "$VLLM_PORT_FILE")"
printf "%s" "$VLLM_PORT" > "$VLLM_PORT_FILE"

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

# Wait for vLLM API to be ready (with timeout)
echo "[launch_vllm_single] Waiting for vLLM API to be ready..."
MAX_WAIT=120
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  if curl -s "http://127.0.0.1:${VLLM_PORT}/health" > /dev/null 2>&1 || \
     curl -s "http://127.0.0.1:${VLLM_PORT}/v1/models" > /dev/null 2>&1; then
    echo "[launch_vllm_single] vLLM API is ready!"
    break
  fi
  if ! kill -0 $VLLM_PID 2>/dev/null; then
    echo "[launch_vllm_single] ERROR: vLLM process died during initialization" >&2
    exit 1
  fi
  sleep 2
  WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
  echo "[launch_vllm_single] WARNING: vLLM API did not become ready within ${MAX_WAIT}s, but process is running" >&2
fi

# Save PID for later management
PID_FILE="${SCRIPT_DIR}/../.vllm_single_pid"
if [[ -e "$PID_FILE" && ! -w "$PID_FILE" ]]; then
  echo "[launch_vllm_single] ⚠ Existing PID file is not writable (${PID_FILE}). Using a temporary location."
  PID_FILE="$(mktemp /tmp/vllm_single_pid_XXXX)"
fi

if ! echo "$VLLM_PID" > "$PID_FILE"; then
  echo "[launch_vllm_single] ⚠ Unable to write PID to ${PID_FILE}. Falling back to /tmp/vllm_single_pid"
  PID_FILE="/tmp/vllm_single_pid"
  echo "$VLLM_PID" > "$PID_FILE"
fi
echo "[launch_vllm_single] PID saved to: ${PID_FILE}"

echo "[launch_vllm_single] vLLM is running"
echo ""
echo "[launch_vllm_single] Access URLs:"
echo "[launch_vllm_single] - vLLM API: http://${NODE_IP}:${VLLM_PORT}"
echo "[launch_vllm_single] - vLLM Docs: http://${NODE_IP}:${VLLM_PORT}/docs"
echo "[launch_vllm_single] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[launch_vllm_single] - Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "[launch_vllm_single] Done"
echo ""
echo "[launch_vllm_single] vLLM is running in the background (PID: ${VLLM_PID})"
echo "[launch_vllm_single] To stop vLLM: kill \$(cat ${PID_FILE})"


