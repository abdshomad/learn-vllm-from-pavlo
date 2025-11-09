#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON_SETUP="$REPO_ROOT/scripts/00_setup_common.sh"

if [[ -f "$COMMON_SETUP" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON_SETUP"
else
  echo "[start_ray_head] ERROR: Unable to locate $COMMON_SETUP" >&2
  exit 1
fi

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

# Ensure no stale Ray head is running
if uv run python -m ray.scripts.scripts status --address "${NODE_IP}:${RAY_PORT}" >/dev/null 2>&1; then
  echo "[start_ray_head] Detected existing Ray cluster at ${NODE_IP}:${RAY_PORT}. Attempting clean shutdown..."
  if uv run python -m ray.scripts.scripts stop --force >/dev/null 2>&1; then
    echo "[start_ray_head] Previous Ray cluster stopped successfully."
  else
    echo "[start_ray_head] ✗ Unable to stop existing Ray cluster automatically."
    echo "[start_ray_head] Please run 'bash scripts/99_shutdown_all.sh' (use sudo if required) and retry."
    exit 1
  fi
fi

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


