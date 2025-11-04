#!/usr/bin/env bash
# Fix Ray Dashboard "No Data" Error
# This script detects when Ray dashboard shows "No data", applies the Prometheus fix,
# and verifies the resolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[fix_ray_dashboard] Starting Ray dashboard 'No data' detection and fix..."
echo ""

NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

RAY_DASHBOARD_URL="http://${NODE_IP}:8265"
PROMETHEUS_URL="http://${NODE_IP}:${PROMETHEUS_PORT}"
SCREENSHOT_DIR="${REPO_ROOT}/screenshots/ray-dashboard-fix"
mkdir -p "$SCREENSHOT_DIR"

# Function to check if Ray dashboard is accessible
check_ray_dashboard_accessible() {
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" "$RAY_DASHBOARD_URL" 2>/dev/null || echo "000")
  if [[ "$status_code" == "200" ]]; then
    return 0
  else
    return 1
  fi
}

# Function to check if Prometheus has Ray targets that are up
check_prometheus_ray_targets() {
  local targets_json
  targets_json=$(curl -s "${PROMETHEUS_URL}/api/v1/targets" 2>/dev/null || echo "")
  
  if [[ -z "$targets_json" ]]; then
    return 1
  fi
  
  # Check if we have Ray targets that are up
  local ray_targets_up
  ray_targets_up=$(echo "$targets_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    targets = d.get('data', {}).get('activeTargets', [])
    ray_targets = [t for t in targets if 'ray' in t['labels'].get('job', '').lower()]
    up_targets = [t for t in ray_targets if t['health'] == 'up']
    if up_targets:
        print('YES')
    else:
        print('NO')
except Exception:
    print('NO')
" 2>/dev/null || echo "NO")
  
  if [[ "$ray_targets_up" == "YES" ]]; then
    return 0
  else
    return 1
  fi
}

# Function to check if Ray metrics exist in Prometheus
check_ray_metrics_in_prometheus() {
  # Try multiple metrics that are more likely to exist
  local metrics_to_check=("ray_cluster_active_nodes" "ray_actors" "ray_cluster_resources_cpu")
  local metrics_response
  
  for metric in "${metrics_to_check[@]}"; do
    metrics_response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${metric}" 2>/dev/null || echo "")
    
    if [[ -z "$metrics_response" ]]; then
      continue
    fi
    
    local has_metrics
    has_metrics=$(echo "$metrics_response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = d.get('data', {}).get('result', [])
    if results:
        print('YES')
    else:
        print('NO')
except Exception:
    print('NO')
" 2>/dev/null || echo "NO")
    
    if [[ "$has_metrics" == "YES" ]]; then
      return 0
    fi
  done
  
  return 1
}

# Function to check if service discovery file exists and has targets
check_service_discovery_file() {
  local sd_file="/tmp/ray/prom_metrics_service_discovery.json"
  
  if [[ ! -f "$sd_file" ]]; then
    return 1
  fi
  
  # Check if file has valid JSON with targets
  local has_targets
  has_targets=$(python3 -c "
import sys, json
try:
    with open('$sd_file', 'r') as f:
        data = json.load(f)
    if isinstance(data, list) and len(data) > 0:
        for item in data:
            if 'targets' in item and len(item['targets']) > 0:
                print('YES')
                sys.exit(0)
    print('NO')
except Exception:
    print('NO')
" 2>/dev/null || echo "NO")
  
  if [[ "$has_targets" == "YES" ]]; then
    return 0
  else
    return 1
  fi
}

# Function to check browser for "No data" text
check_browser_no_data() {
  local helper_script="${SCRIPT_DIR}/helpers/detect_no_data_browser.py"
  
  if [[ ! -f "$helper_script" ]]; then
    return 2  # Helper not available
  fi
  
  if command -v python3 >/dev/null 2>&1; then
    if python3 "$helper_script" "$RAY_DASHBOARD_URL" 2>/dev/null; then
      return 0  # "No data" detected
    else
      local exit_code=$?
      if [[ $exit_code -eq 1 ]]; then
        return 1  # No "No data" found
      else
        return 2  # Error/helper unavailable
      fi
    fi
  fi
  
  return 2  # Python not available
}

# Function to check Grafana status
check_grafana_status() {
  # Check if Grafana service is running
  if systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo "[fix_ray_dashboard] ✓ Grafana service is running"
    return 0
  else
    echo "[fix_ray_dashboard] ⚠ Grafana service is not running"
    echo "[fix_ray_dashboard]   Note: Ray dashboard requires both Prometheus AND Grafana to display charts"
    echo "[fix_ray_dashboard]   Start Grafana with: sudo systemctl start grafana-server"
    return 1
  fi
}

# Function to detect "No data" issue
detect_no_data_issue() {
  echo "[fix_ray_dashboard] Checking for 'No data' issue..."
  
  # Check if Ray dashboard is accessible
  if ! check_ray_dashboard_accessible; then
    echo "[fix_ray_dashboard] ⚠ Ray dashboard is not accessible at $RAY_DASHBOARD_URL"
    echo "[fix_ray_dashboard]   Skipping fix (Ray may not be running)"
    return 1
  fi
  echo "[fix_ray_dashboard] ✓ Ray dashboard is accessible"
  
  # Check Grafana status
  check_grafana_status || true  # Don't fail if Grafana is not running, just warn
  
  # Try browser-based detection first
  echo "[fix_ray_dashboard] Checking dashboard via browser..."
  check_browser_no_data
  local browser_result=$?
  case $browser_result in
    0)
      echo "[fix_ray_dashboard] ✗ Browser detected 'No data' text in dashboard"
      return 0  # Issue detected
      ;;
    1)
      echo "[fix_ray_dashboard] ✓ Browser did not detect 'No data' text"
      ;;
    2)
      echo "[fix_ray_dashboard] ⚠ Browser detection unavailable, using API checks"
      ;;
  esac
  
  # Check service discovery file
  if ! check_service_discovery_file; then
    echo "[fix_ray_dashboard] ⚠ Service discovery file not found or empty"
    echo "[fix_ray_dashboard]   Waiting for Ray to create service discovery file..."
    # Wait up to 30 seconds for Ray to create the file
    local waited=0
    while [[ $waited -lt 30 ]]; do
      sleep 2
      waited=$((waited + 2))
      if check_service_discovery_file; then
        echo "[fix_ray_dashboard] ✓ Service discovery file found"
        break
      fi
    done
    
    if ! check_service_discovery_file; then
      echo "[fix_ray_dashboard] ✗ Service discovery file still not found after waiting"
      return 1
    fi
  else
    echo "[fix_ray_dashboard] ✓ Service discovery file exists"
  fi
  
  # Check Prometheus targets
  if ! check_prometheus_ray_targets; then
    echo "[fix_ray_dashboard] ✗ Prometheus does not have Ray targets that are 'up'"
    return 0  # Issue detected
  fi
  echo "[fix_ray_dashboard] ✓ Prometheus has Ray targets that are 'up'"
  
  # Check for Ray metrics
  if ! check_ray_metrics_in_prometheus; then
    echo "[fix_ray_dashboard] ✗ Ray metrics not found in Prometheus"
    return 0  # Issue detected
  fi
  echo "[fix_ray_dashboard] ✓ Ray metrics found in Prometheus"
  
  echo "[fix_ray_dashboard] ✓ No issues detected - Ray dashboard should be working"
  return 1  # No issue
}

# Function to take screenshot (requires Python helper or manual)
take_screenshot() {
  local filename="$1"
  local url="$2"
  local description="$3"
  
  echo "[fix_ray_dashboard] Taking screenshot: $description"
  echo "[fix_ray_dashboard] URL: $url"
  
  # Try to use Python helper if available
  if command -v python3 >/dev/null 2>&1; then
    local helper_script="${SCRIPT_DIR}/helpers/take_browser_screenshot.py"
    if [[ -f "$helper_script" ]]; then
      python3 "$helper_script" "$url" "$filename" "$description" 2>/dev/null && return 0
    fi
  fi
  
  # Fallback: save instruction for manual screenshot
  local instruction_file="${SCREENSHOT_DIR}/INSTRUCTIONS.txt"
  {
    echo "Screenshot instruction: $description"
    echo "URL: $url"
    echo "Save to: $filename"
    echo "Timestamp: $(date)"
    echo ""
  } >> "$instruction_file"
  
  echo "[fix_ray_dashboard] ⚠ Screenshot helper not available - instruction saved to $instruction_file"
  echo "[fix_ray_dashboard]   Please take a screenshot of $url and save it as $filename"
}

# Function to apply the fix
apply_fix() {
  echo ""
  echo "[fix_ray_dashboard] Applying Prometheus configuration fix..."
  
  # Check if we need sudo
  if [[ $EUID -ne 0 ]]; then
    echo "[fix_ray_dashboard] Running fix script with sudo..."
    sudo bash "$SCRIPT_DIR/05c_fix_prometheus_config.sh"
  else
    bash "$SCRIPT_DIR/05c_fix_prometheus_config.sh"
  fi
  
  echo "[fix_ray_dashboard] ✓ Prometheus configuration updated"
  
  # Wait for Prometheus to restart and scrape metrics
  echo "[fix_ray_dashboard] Waiting for Prometheus to scrape metrics..."
  sleep 5
  
  # Wait up to 30 seconds for metrics to appear
  local waited=0
  while [[ $waited -lt 30 ]]; do
    if check_ray_metrics_in_prometheus; then
      echo "[fix_ray_dashboard] ✓ Ray metrics detected in Prometheus"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  
  echo "[fix_ray_dashboard] ⚠ Ray metrics may not be fully available yet (waited 30s)"
  return 0
}

# Function to verify the fix
verify_fix() {
  echo ""
  echo "[fix_ray_dashboard] Verifying fix..."
  
  local all_good=true
  
  # Check Prometheus targets
  if check_prometheus_ray_targets; then
    echo "[fix_ray_dashboard] ✓ Prometheus has Ray targets that are 'up'"
  else
    echo "[fix_ray_dashboard] ✗ Prometheus still does not have Ray targets that are 'up'"
    all_good=false
  fi
  
  # Check Ray metrics
  if check_ray_metrics_in_prometheus; then
    echo "[fix_ray_dashboard] ✓ Ray metrics are available in Prometheus"
  else
    echo "[fix_ray_dashboard] ✗ Ray metrics still not available in Prometheus"
    all_good=false
  fi
  
  if [[ "$all_good" == "true" ]]; then
    echo "[fix_ray_dashboard] ✓ Fix verification successful"
    return 0
  else
    echo "[fix_ray_dashboard] ⚠ Some verification checks failed, but continuing..."
    return 0  # Don't fail the script
  fi
}

# Main execution
main() {
  # Detect the issue
  if ! detect_no_data_issue; then
    echo "[fix_ray_dashboard] No 'No data' issue detected - exiting"
    exit 0
  fi
  
  echo ""
  echo "[fix_ray_dashboard] ✗ 'No data' issue detected!"
  
  # Take screenshot before fix
  take_screenshot \
    "${SCREENSHOT_DIR}/01-no-data-detected.png" \
    "$RAY_DASHBOARD_URL" \
    "Ray Dashboard showing No data before fix"
  
  # Apply the fix
  apply_fix
  
  # Verify the fix
  verify_fix
  
  # Wait a bit more for dashboard to update
  echo "[fix_ray_dashboard] Waiting for dashboard to update..."
  sleep 5
  
  # Take screenshot after fix
  take_screenshot \
    "${SCREENSHOT_DIR}/02-after-fix.png" \
    "$RAY_DASHBOARD_URL" \
    "Ray Dashboard after fix (should show data)"
  
  echo ""
  echo "[fix_ray_dashboard] Fix process complete!"
  echo "[fix_ray_dashboard] Screenshots saved to: $SCREENSHOT_DIR"
  echo "[fix_ray_dashboard] Ray Dashboard: $RAY_DASHBOARD_URL"
  echo "[fix_ray_dashboard] Prometheus: $PROMETHEUS_URL"
}

# Run main function
main "$@"

