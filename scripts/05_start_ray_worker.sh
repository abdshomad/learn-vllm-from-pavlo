#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

HEAD_NODE_IP="${HEAD_NODE_IP:-}"
WORKER_NODE_IP="${WORKER_NODE_IP:-}"

if [[ -z "${WORKER_NODE_IP}" ]]; then
  WORKER_NODE_IP="$(primary_ip)"
fi

if [[ -z "${HEAD_NODE_IP}" ]]; then
  echo "[start_ray_worker] ERROR: HEAD_NODE_IP is required" >&2
  exit 1
fi

# Configure Ray monitoring integration
export RAY_GRAFANA_HOST="http://${WORKER_NODE_IP}:${GRAFANA_PORT}"
export RAY_PROMETHEUS_HOST="http://${WORKER_NODE_IP}:${PROMETHEUS_PORT}"
export RAY_GRAFANA_IFRAME_HOST="http://${WORKER_NODE_IP}:${GRAFANA_PORT}"

echo "[start_ray_worker] Starting Ray worker with monitoring integration"
echo "[start_ray_worker] Worker node: ${WORKER_NODE_IP}"
echo "[start_ray_worker] Joining cluster at: ${HEAD_NODE_IP}:${RAY_PORT}"
echo "[start_ray_worker] Grafana: ${RAY_GRAFANA_HOST}"
echo "[start_ray_worker] Prometheus: ${RAY_PROMETHEUS_HOST}"

uv run ray start --address "${HEAD_NODE_IP}:${RAY_PORT}" --node-ip-address "${WORKER_NODE_IP}"

echo "[start_ray_worker] Waiting for worker to initialize..."
sleep 3

echo "[start_ray_worker] Ray cluster status:"
uv run ray status || echo "[start_ray_worker] Warning: ray status unavailable"

echo ""
echo "[start_ray_worker] Access URLs:"
echo "[start_ray_worker] - Ray Dashboard: http://${WORKER_NODE_IP}:8265"
echo "[start_ray_worker] - Prometheus: http://${WORKER_NODE_IP}:${PROMETHEUS_PORT}"
echo "[start_ray_worker] - Grafana: http://${WORKER_NODE_IP}:${GRAFANA_PORT}"

echo "[start_ray_worker] Done"


