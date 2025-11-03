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
uv run ray start --head --node-ip-address "$NODE_IP" --port "$RAY_PORT"
uv run ray status || true
echo "[start_ray_head] Done"


