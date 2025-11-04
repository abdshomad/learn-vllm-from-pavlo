#!/usr/bin/env bash
# Verify that Prometheus is correctly scraping Ray metrics

set -euo pipefail

echo "=== Verifying Prometheus Configuration ==="
echo ""

# Check Prometheus targets
echo "1. Checking Prometheus targets..."
TARGETS=$(curl -s "http://10.10.10.13:9090/api/v1/targets" 2>/dev/null | python3 -c "
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
        print(\"  ✗ No Ray targets found\")
except Exception as e:
    print(f\"  ✗ Error: {e}\")
")

echo "$TARGETS"
echo ""

# Check if Ray metrics exist in Prometheus
echo "2. Checking if Ray metrics are in Prometheus..."
METRICS=$(curl -s "http://10.10.10.13:9090/api/v1/query?query=ray_cluster_resources_cpu" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = d.get('data', {}).get('result', [])
    if results:
        print(f\"  ✓ Found {len(results)} Ray metric(s)\")
        print(f\"  Sample: {results[0].get('metric', {})}\")
    else:
        print(\"  ✗ No Ray metrics found in Prometheus\")
except Exception as e:
    print(f\"  ✗ Error: {e}\")
")

echo "$METRICS"
echo ""

# Check Grafana datasource
echo "3. Checking Grafana datasource..."
GRAFANA=$(curl -s -u admin:admin "http://10.10.10.13:3000/api/datasources" 2>/dev/null | python3 -c "
import sys, json
try:
    ds_list = json.load(sys.stdin)
    prom_ds = [ds for ds in ds_list if ds.get('type') == 'prometheus']
    if prom_ds:
        print(f\"  ✓ Prometheus datasource configured: {prom_ds[0].get('name')}\")
    else:
        print(\"  ✗ Prometheus datasource not found\")
except Exception as e:
    print(f\"  ✗ Error: {e}\")
")

echo "$GRAFANA"
echo ""

echo "=== Summary ==="
echo "If all checks show ✓, the fix is complete!"
echo "If any show ✗, run: sudo bash scripts/05c_fix_prometheus_config.sh"
