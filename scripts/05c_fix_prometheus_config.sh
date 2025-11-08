#!/usr/bin/env bash
# Quick fix for Prometheus configuration to use Ray service discovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() {
  echo "[fix_prometheus_config] $*"
}

require_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi

  if sudo -n true 2>/dev/null; then
    exec sudo "$0" "$@"
  fi

  log "⚠ This fix requires root privileges."
  log "   Run manually with: sudo bash $0"
  exit 0
}

require_root "$@"

log "Updating /etc/prometheus/prometheus.yml"
RAY_TMPDIR_PATH="${RAY_TMPDIR:-${REPO_ROOT}/.ray_tmp}"
cat > /etc/prometheus/prometheus.yml <<EOF
# Prometheus configuration for Ray cluster monitoring
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'ray-cluster'

# Scrape Prometheus itself
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Scrape Ray metrics using service discovery
  # Ray 2.x exposes metrics on ports discovered via ${RAY_TMPDIR_PATH}/prom_metrics_service_discovery.json
  - job_name: 'ray'
    scrape_interval: 15s
    file_sd_configs:
      - files:
          - ${RAY_TMPDIR_PATH}/prom_metrics_service_discovery.json
        refresh_interval: 30s
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

log "Restarting Prometheus service"
systemctl restart prometheus

log "✓ Prometheus configuration updated and service restarted"
