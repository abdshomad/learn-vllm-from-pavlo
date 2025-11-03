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

echo "[start_ray_worker] Joining worker ${WORKER_NODE_IP} to ${HEAD_NODE_IP}:${RAY_PORT}"
uv run ray start --address "${HEAD_NODE_IP}:${RAY_PORT}" --node-ip-address "${WORKER_NODE_IP}"

echo "[start_ray_worker] Waiting for worker to initialize..."
sleep 3

echo "[start_ray_worker] Ray cluster status:"
uv run ray status || echo "[start_ray_worker] Warning: ray status unavailable"

echo "[start_ray_worker] Done"


