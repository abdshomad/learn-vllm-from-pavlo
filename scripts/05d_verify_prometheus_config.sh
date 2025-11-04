#!/usr/bin/env bash
# Verify that Prometheus is correctly scraping Ray metrics

set -u  # Don't fail on undefined variables, but allow pipefail for error handling
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

# Get node IP if not set
NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

PROMETHEUS_URL="http://${NODE_IP}:${PROMETHEUS_PORT}"
GRAFANA_URL="http://${NODE_IP}:${GRAFANA_PORT}"

echo "=== Verifying Prometheus Configuration ==="
echo "Prometheus URL: ${PROMETHEUS_URL}"
echo "Grafana URL: ${GRAFANA_URL}"
echo ""

# Check if Prometheus is accessible
if ! curl -s --max-time 5 "${PROMETHEUS_URL}/-/healthy" >/dev/null 2>&1; then
    echo "⚠ Prometheus is not accessible at ${PROMETHEUS_URL}"
    echo "  This may be expected if Ray is not running yet."
    exit 0  # Don't fail the script, just warn
fi

# Check Prometheus targets
echo "1. Checking Prometheus targets..."
TARGETS_OUTPUT=$(curl -s --max-time 5 "${PROMETHEUS_URL}/api/v1/targets" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    targets = d.get('data', {}).get('activeTargets', [])
    ray_targets = [t for t in targets if 'ray' in t['labels'].get('job', '').lower()]
    if ray_targets:
        for t in ray_targets:
            print(f\"  {t['labels']['job']}: {t['health']} - {t['scrapeUrl']}\")
        print(f\"  ✓ Found {len(ray_targets)} Ray target(s)\")
    else:
        print(\"  ⚠ No Ray targets found (Ray may not be running)\")
except Exception as e:
    print(f\"  ⚠ Error parsing targets: {e}\")
" 2>/dev/null || echo "  ⚠ Unable to check Prometheus targets")

echo "$TARGETS_OUTPUT"
echo ""

# Check if Ray metrics exist in Prometheus
echo "2. Checking if Ray metrics are in Prometheus..."
METRICS_OUTPUT=$(curl -s --max-time 5 "${PROMETHEUS_URL}/api/v1/query?query=ray_cluster_resources_cpu" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = d.get('data', {}).get('result', [])
    if results:
        print(f\"  ✓ Found {len(results)} Ray metric(s)\")
        print(f\"  Sample: {results[0].get('metric', {})}\")
    else:
        print(\"  ⚠ No Ray metrics found in Prometheus (Ray may not be running)\")
except Exception as e:
    print(f\"  ⚠ Error querying metrics: {e}\")
" 2>/dev/null || echo "  ⚠ Unable to check Ray metrics")

echo "$METRICS_OUTPUT"
echo ""

# Check Grafana datasource
echo "3. Checking Grafana datasource..."
if ! curl -s --max-time 5 "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
    echo "  ⚠ Grafana is not accessible at ${GRAFANA_URL}"
else
    GRAFANA_OUTPUT=$(curl -s --max-time 5 -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" "${GRAFANA_URL}/api/datasources" 2>/dev/null | python3 -c "
import sys, json
try:
    ds_list = json.load(sys.stdin)
    prom_ds = [ds for ds in ds_list if ds.get('type') == 'prometheus']
    if prom_ds:
        print(f\"  ✓ Prometheus datasource configured: {prom_ds[0].get('name')}\")
    else:
        print(\"  ⚠ Prometheus datasource not found\")
except Exception as e:
    print(f\"  ⚠ Error checking datasource: {e}\")
" 2>/dev/null || echo "  ⚠ Unable to check Grafana datasource")
    echo "$GRAFANA_OUTPUT"
fi

echo ""
echo "=== Summary ==="
echo "Note: Some checks may show warnings if Ray is not running."
echo "This is expected if you're running verification before starting Ray."
