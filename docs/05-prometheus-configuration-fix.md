# Prometheus Configuration Fix for Ray Dashboard Cluster Utilization

## Problem
The Ray Dashboard's "Cluster Utilization" panel shows "No data" because Prometheus is configured to scrape Ray metrics from an incorrect endpoint (`http://10.10.10.13:8265/metrics` which returns 404).

## Root Cause
- Ray 2.x exposes Prometheus metrics on dynamic ports (e.g., `63408`, `44217`, `44227`)
- These endpoints are automatically discovered and listed in `/tmp/ray/prom_metrics_service_discovery.json`
- The current Prometheus configuration uses a static endpoint that doesn't exist

## Solution
Update Prometheus to use file-based service discovery to automatically find and scrape Ray metrics endpoints.

## Quick Fix

Run the following command (requires sudo):

```bash
sudo bash scripts/05c_fix_prometheus_config.sh
```

This script will:
1. Update `/etc/prometheus/prometheus.yml` to use file-based service discovery
2. Restart Prometheus service
3. Enable Prometheus to automatically discover and scrape Ray metrics

## Verification

After running the fix, verify it worked:

```bash
bash scripts/05d_verify_prometheus_config.sh
```

This will check:
- ✅ Prometheus targets are healthy
- ✅ Ray metrics are being collected
- ✅ Grafana datasource is configured

## Expected Results

After the fix:
1. **Prometheus targets**: Ray targets should show as "up" instead of "down"
2. **Ray Dashboard**: "Cluster Utilization" panel should show graphs instead of "No data"
3. **Grafana**: Dashboard should display cluster metrics

## Technical Details

### Current Configuration (Incorrect)
```yaml
- job_name: 'ray-head'
  static_configs:
    - targets: ['10.10.10.13:8265']
  metrics_path: '/metrics'  # This endpoint doesn't exist
```

### Fixed Configuration (Correct)
```yaml
- job_name: 'ray'
  scrape_interval: 15s
  file_sd_configs:
    - files:
        - /tmp/ray/prom_metrics_service_discovery.json
      refresh_interval: 30s
```

### Service Discovery File
Ray automatically creates `/tmp/ray/prom_metrics_service_discovery.json` with:
```json
[
  {
    "labels": {"job": "ray"},
    "targets": [
      "10.10.10.13:63408",
      "10.10.10.13:44217",
      "10.10.10.13:44227"
    ]
  }
]
```

## Files Created

- `scripts/05c_fix_prometheus_config.sh` - Quick fix script
- `scripts/05d_verify_prometheus_config.sh` - Verification script
- `scripts/05a_configure_monitoring.sh` - Updated monitoring configuration script (for future use)

## Screenshots

Screenshots documenting the fix process are available in:
- Before fix: `screenshots/ray-serve-deployment/08-cluster-utilization-no-data.png`
- After fix: `screenshots/prometheus-fix/` (contains all verification screenshots)

