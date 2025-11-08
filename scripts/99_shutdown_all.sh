#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "=========================================="
echo "[shutdown_all] Shutting down GPU Cluster"
echo "=========================================="
echo ""

# Detect primary IP
NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

# Ports used by the cluster
RAY_PORT="${RAY_PORT:-6379}"
RAY_DASHBOARD_PORT=8265
VLLM_PORT="${VLLM_PORT:-8000}"
SERVE_PORT="${SERVE_PORT:-8001}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

# Function to kill processes on a specific port
kill_port() {
  local port="$1"
  local name="$2"
  
  if lsof -ti:"$port" >/dev/null 2>&1; then
    echo "[shutdown_all] Stopping processes on port $port ($name)..."
    lsof -ti:"$port" | xargs -r kill -9 2>/dev/null || true
    sleep 1
    echo "[shutdown_all] ✓ Port $port cleared"
  else
    echo "[shutdown_all] ✓ Port $port ($name) already free"
  fi
}

# Function to kill processes by name pattern
kill_processes() {
  local pattern="$1"
  local name="$2"
  
  local pids
  pids=$(pgrep -f "$pattern" 2>/dev/null || true)
  
  if [[ -n "$pids" ]]; then
    echo "[shutdown_all] Stopping $name processes..."
    echo "$pids" | xargs -r kill -9 2>/dev/null || true
    sleep 1
    echo "[shutdown_all] ✓ $name processes stopped"
  else
    echo "[shutdown_all] ✓ No $name processes found"
  fi
}

# Function to kill GPU processes
kill_gpu_processes() {
  echo "[shutdown_all] Checking for GPU processes..."
  
  if command -v nvidia-smi >/dev/null 2>&1; then
    # Get PIDs of processes using GPU
    local gpu_pids
    gpu_pids=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | grep -v '^$' || true)
    
    if [[ -n "$gpu_pids" ]]; then
      echo "[shutdown_all] Found GPU processes: $gpu_pids"
      echo "[shutdown_all] Stopping GPU processes..."
      
      # Kill each GPU process
      while IFS= read -r pid; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          echo "[shutdown_all]   Killing PID $pid"
          kill -9 "$pid" 2>/dev/null || true
        fi
      done <<< "$gpu_pids"
      
      sleep 2
      echo "[shutdown_all] ✓ GPU processes stopped"
    else
      echo "[shutdown_all] ✓ No GPU processes found"
    fi
  else
    echo "[shutdown_all] ⚠ nvidia-smi not available, skipping GPU process check"
  fi
}

# 1. Stop Ray Serve deployments
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 1: Stopping Ray Serve deployments"
echo "[shutdown_all] =========================================="
if uv run python -m ray.scripts.scripts status >/dev/null 2>&1; then
  echo "[shutdown_all] Ray cluster is running, checking for Serve deployments..."
  
  # Try to shutdown Ray Serve if it's deployed
  if uv run python -c "import ray; ray.init(); from ray import serve; serve.shutdown()" 2>/dev/null; then
    echo "[shutdown_all] ✓ Ray Serve shutdown initiated"
  else
    echo "[shutdown_all] ⚠ Ray Serve shutdown failed or not deployed"
  fi
else
  echo "[shutdown_all] ✓ Ray cluster not running, skipping Serve shutdown"
fi
echo ""

# 2. Stop Ray cluster
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 2: Stopping Ray cluster"
echo "[shutdown_all] =========================================="
if uv run python -m ray.scripts.scripts status >/dev/null 2>&1; then
  echo "[shutdown_all] Stopping Ray cluster..."
  uv run python -m ray.scripts.scripts stop --force 2>/dev/null || true
  sleep 2
  echo "[shutdown_all] ✓ Ray cluster stopped"
else
  echo "[shutdown_all] ✓ Ray cluster not running"
fi
echo ""

# 3. Stop vLLM processes
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 3: Stopping vLLM processes"
echo "[shutdown_all] =========================================="
kill_processes "vllm.entrypoints.openai.api_server" "vLLM API"
kill_processes "python.*vllm" "vLLM Python"
echo ""

# 4. Stop monitoring services (systemd)
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 4: Stopping monitoring services"
echo "[shutdown_all] =========================================="

# Stop Prometheus
if systemctl list-units --type=service --state=running | grep -q prometheus.service; then
  echo "[shutdown_all] Stopping Prometheus service..."
  sudo systemctl stop prometheus 2>/dev/null || true
  echo "[shutdown_all] ✓ Prometheus stopped"
else
  echo "[shutdown_all] ✓ Prometheus service not running"
fi

# Stop Grafana
if systemctl list-units --type=service --state=running | grep -q grafana-server.service; then
  echo "[shutdown_all] Stopping Grafana service..."
  sudo systemctl stop grafana-server 2>/dev/null || true
  echo "[shutdown_all] ✓ Grafana stopped"
else
  echo "[shutdown_all] ✓ Grafana service not running"
fi
echo ""

# 5. Kill processes on specific ports
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 5: Clearing cluster ports"
echo "[shutdown_all] =========================================="
kill_port "$RAY_PORT" "Ray"
kill_port "$RAY_DASHBOARD_PORT" "Ray Dashboard"
kill_port "$VLLM_PORT" "vLLM API"
kill_port "$SERVE_PORT" "Ray Serve"
kill_port "$PROMETHEUS_PORT" "Prometheus"
kill_port "$GRAFANA_PORT" "Grafana"
echo ""

# 6. Kill any remaining Ray processes
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 6: Cleaning up Ray processes"
echo "[shutdown_all] =========================================="
kill_processes "ray.*start" "Ray start"
kill_processes "raylet" "Raylet"
kill_processes "gcs_server" "Ray GCS"
kill_processes "dashboard" "Ray Dashboard"
echo ""

# 7. Kill GPU processes
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 7: Stopping GPU processes"
echo "[shutdown_all] =========================================="
kill_gpu_processes
echo ""

# 8. Final verification
echo "[shutdown_all] =========================================="
echo "[shutdown_all] Step 8: Final verification"
echo "[shutdown_all] =========================================="

# Check Ray
if uv run python -m ray.scripts.scripts status >/dev/null 2>&1; then
  echo "[shutdown_all] ⚠ WARNING: Ray cluster still appears to be running"
else
  echo "[shutdown_all] ✓ Ray cluster confirmed stopped"
fi

# Check ports
ports_clear=true
for port in "$RAY_PORT" "$RAY_DASHBOARD_PORT" "$VLLM_PORT" "$SERVE_PORT" "$PROMETHEUS_PORT" "$GRAFANA_PORT"; do
  if lsof -ti:"$port" >/dev/null 2>&1; then
    echo "[shutdown_all] ⚠ WARNING: Port $port still in use"
    ports_clear=false
  fi
done

if [[ "$ports_clear" == "true" ]]; then
  echo "[shutdown_all] ✓ All cluster ports are free"
fi

# Check GPU
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_pids=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | grep -v '^$' || true)
  if [[ -n "$gpu_pids" ]]; then
    echo "[shutdown_all] ⚠ WARNING: GPU processes still running: $gpu_pids"
  else
    echo "[shutdown_all] ✓ No GPU processes detected"
  fi
fi

echo ""
echo "=========================================="
echo "[shutdown_all] Shutdown complete!"
echo "=========================================="
echo ""
echo "[shutdown_all] Summary:"
echo "[shutdown_all] - Ray cluster: stopped"
echo "[shutdown_all] - vLLM processes: stopped"
echo "[shutdown_all] - Monitoring services: stopped"
echo "[shutdown_all] - GPU processes: stopped"
echo "[shutdown_all] - Cluster ports: cleared"
echo ""
