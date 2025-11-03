#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

echo "[start_ray_head] Starting Ray head on ${NODE_IP}:${RAY_PORT}"
uv run ray start --head --node-ip-address "$NODE_IP" --port "$RAY_PORT" --dashboard-host 0.0.0.0

echo "[start_ray_head] Waiting for Ray to initialize..."
sleep 3

echo "[start_ray_head] Ray cluster status:"
uv run ray status || echo "[start_ray_head] Warning: ray status unavailable"

echo ""
echo "[start_ray_head] Ray dashboard available at: http://${NODE_IP}:8265"
echo "[start_ray_head] Done"


