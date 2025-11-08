#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

# Configure Ray monitoring integration
export RAY_GRAFANA_HOST="http://${NODE_IP}:${GRAFANA_PORT}"
export RAY_PROMETHEUS_HOST="http://${NODE_IP}:${PROMETHEUS_PORT}"
export RAY_GRAFANA_IFRAME_HOST="http://${NODE_IP}:${GRAFANA_PORT}"

echo "[start_ray_head] Starting Ray head with monitoring integration"
echo "[start_ray_head] Head node: ${NODE_IP}"
echo "[start_ray_head] Grafana: ${RAY_GRAFANA_HOST}"
echo "[start_ray_head] Prometheus: ${RAY_PROMETHEUS_HOST}"

uv run python -m ray.scripts.scripts start --head --node-ip-address "$NODE_IP" --port "$RAY_PORT" --dashboard-host 0.0.0.0

echo "[start_ray_head] Waiting for Ray to initialize..."
sleep 3

echo "[start_ray_head] Ray cluster status:"
uv run python -m ray.scripts.scripts status || echo "[start_ray_head] Warning: ray status unavailable"

echo ""
echo "[start_ray_head] Access URLs:"
echo "[start_ray_head] - Ray Dashboard: http://${NODE_IP}:8265"
echo "[start_ray_head] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[start_ray_head] - Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "[start_ray_head] Done"


