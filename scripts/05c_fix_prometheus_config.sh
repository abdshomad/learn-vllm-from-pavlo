#!/bin/bash
# Quick fix for Prometheus configuration to use Ray service discovery

sudo bash -c 'cat > /etc/prometheus/prometheus.yml << '\''ENDOFFILE'\''
# Prometheus configuration for Ray cluster monitoring
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: '\''ray-cluster'\''

# Scrape Prometheus itself
scrape_configs:
  - job_name: '\''prometheus'\''
    static_configs:
      - targets: ['\''localhost:9090'\'']

  # Scrape Ray metrics using service discovery
  # Ray 2.x exposes metrics on ports discovered via /tmp/ray/prom_metrics_service_discovery.json
  - job_name: '\''ray'\''
    scrape_interval: 15s
    file_sd_configs:
      - files:
          - /tmp/ray/prom_metrics_service_discovery.json
        refresh_interval: 30s
ENDOFFILE
chown prometheus:prometheus /etc/prometheus/prometheus.yml
systemctl restart prometheus
echo "✓ Prometheus configuration updated and restarted"
'
