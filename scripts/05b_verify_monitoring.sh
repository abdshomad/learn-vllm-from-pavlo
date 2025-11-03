#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[verify_monitoring] Verifying Prometheus and Grafana configuration..."

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

# Check if services are running
echo "[verify_monitoring] Checking service status..."

# Check Prometheus
if systemctl is-active --quiet prometheus 2>/dev/null; then
  echo "[verify_monitoring] ✓ Prometheus service is running"
else
  echo "[verify_monitoring] ✗ Prometheus service is not running"
  if [[ $EUID -eq 0 ]]; then
    echo "[verify_monitoring] Service status:"
    systemctl status prometheus --no-pager -l | head -15 || true
  else
    echo "[verify_monitoring] Run with sudo to see service status"
  fi
fi

# Check Grafana
if systemctl is-active --quiet grafana-server 2>/dev/null; then
  echo "[verify_monitoring] ✓ Grafana service is running"
else
  echo "[verify_monitoring] ✗ Grafana service is not running"
  if [[ $EUID -eq 0 ]]; then
    echo "[verify_monitoring] Service status:"
    systemctl status grafana-server --no-pager -l | head -15 || true
  else
    echo "[verify_monitoring] Run with sudo to see service status"
  fi
fi

echo ""

# Check Prometheus web UI
echo "[verify_monitoring] Checking Prometheus web interface..."
PROM_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PROMETHEUS_PORT}" 2>/dev/null || echo "000")
if [[ "$PROM_STATUS" == "200" ]]; then
  echo "[verify_monitoring] ✓ Prometheus web UI accessible at http://${NODE_IP}:${PROMETHEUS_PORT}"
else
  echo "[verify_monitoring] ✗ Prometheus web UI not accessible (HTTP $PROM_STATUS)"
fi

# Check Grafana web UI
echo "[verify_monitoring] Checking Grafana web interface..."
GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GRAFANA_PORT}" 2>/dev/null || echo "000")
if [[ "$GRAFANA_STATUS" == "200" || "$GRAFANA_STATUS" == "302" ]]; then
  echo "[verify_monitoring] ✓ Grafana web UI accessible at http://${NODE_IP}:${GRAFANA_PORT}"
else
  echo "[verify_monitoring] ✗ Grafana web UI not accessible (HTTP $GRAFANA_STATUS)"
fi

echo ""

# Check Ray metrics endpoint (if Ray is running)
if command -v ray >/dev/null 2>&1; then
  echo "[verify_monitoring] Checking Ray metrics availability..."
  RAY_METRICS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8265/metrics" 2>/dev/null || echo "000")
  if [[ "$RAY_METRICS" == "200" ]]; then
    echo "[verify_monitoring] ✓ Ray metrics endpoint accessible at http://${NODE_IP}:8265/metrics"
    
    # Check for specific Ray metrics
    echo "[verify_monitoring] Checking for Ray metrics..."
    RAY_METRICS_COUNT=$(curl -s "http://localhost:8265/metrics" 2>/dev/null | grep -c "^ray_" || echo "0")
    echo "[verify_monitoring] Found $RAY_METRICS_COUNT Ray metrics"
  else
    echo "[verify_monitoring] ✗ Ray metrics endpoint not accessible (HTTP $RAY_METRICS)"
    echo "[verify_monitoring]  (This is normal if Ray is not running or not configured)"
  fi
fi

echo ""

# Check if Prometheus can scrape Ray metrics
if command -v curl >/dev/null 2>&1; then
  echo "[verify_monitoring] Checking Prometheus targets..."
  
  # Try to get targets from Prometheus API (may fail if not configured)
  PROM_TARGETS=$(curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null || echo "")
  
  if [[ -n "$PROM_TARGETS" ]]; then
    # Parse JSON to check if we have any scrape targets
    if echo "$PROM_TARGETS" | grep -q "activeTargets"; then
      echo "[verify_monitoring] ✓ Prometheus has targets configured"
      
      # Check if Ray targets are up
      RAY_TARGETS=$(echo "$PROM_TARGETS" | grep -c "ray" || echo "0")
      if [[ "$RAY_TARGETS" -gt 0 ]]; then
        echo "[verify_monitoring] ✓ Prometheus has $RAY_TARGETS Ray target(s)"
      fi
    else
      echo "[verify_monitoring] ⚠ Prometheus targets API responded but no targets found"
    fi
  else
    echo "[verify_monitoring] ⚠ Could not query Prometheus targets API"
  fi
fi

echo ""

# Check Grafana datasources
echo "[verify_monitoring] Checking Grafana datasources..."
GRAFANA_DS=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" "http://localhost:${GRAFANA_PORT}/api/datasources" 2>/dev/null || echo "")
if echo "$GRAFANA_DS" | grep -q "Prometheus"; then
  echo "[verify_monitoring] ✓ Grafana has Prometheus datasource configured"
else
  echo "[verify_monitoring] ✗ Grafana Prometheus datasource not configured"
fi

echo ""

# Check Grafana dashboards
echo "[verify_monitoring] Checking Grafana dashboards..."
GRAFANA_DASHBOARDS=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" "http://localhost:${GRAFANA_PORT}/api/search?query=ray" 2>/dev/null || echo "")
if echo "$GRAFANA_DASHBOARDS" | grep -q "Ray"; then
  DASHBOARD_COUNT=$(echo "$GRAFANA_DASHBOARDS" | grep -c '"title":' || echo "0")
  echo "[verify_monitoring] ✓ Found $DASHBOARD_COUNT Ray dashboard(s) in Grafana"
else
  echo "[verify_monitoring] ⚠ No Ray dashboards found in Grafana"
fi

echo ""
echo "[verify_monitoring] Verification complete"
echo ""
echo "[verify_monitoring] Access URLs:"
echo "[verify_monitoring] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[verify_monitoring] - Grafana: http://${NODE_IP}:${GRAFANA_PORT} (default: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})"
echo "[verify_monitoring] - Ray Dashboard: http://${NODE_IP}:8265"

