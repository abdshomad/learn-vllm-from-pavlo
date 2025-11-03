#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[configure_monitoring] Configuring Prometheus and Grafana for Ray..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "[configure_monitoring] ERROR: This script must be run as root" >&2
  echo "[configure_monitoring] Please run with sudo" >&2
  exit 1
fi

# Detect Ray head node
NODE_IP="${NODE_IP:-}"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(primary_ip)"
fi

echo "[configure_monitoring] Configuring for Ray head at ${NODE_IP}:${RAY_PORT}"

# Configure Prometheus to scrape Ray metrics
echo "[configure_monitoring] Configuring Prometheus to scrape Ray metrics..."
cat > /etc/prometheus/prometheus.yml << EOF
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

  # Scrape Ray head node metrics
  - job_name: 'ray-head'
    scrape_interval: 15s
    static_configs:
      - targets: ['${NODE_IP}:8265']
    metrics_path: '/metrics'

  # Scrape Ray worker nodes (add more if needed)
  - job_name: 'ray-workers'
    scrape_interval: 15s
    static_configs:
      - targets: ['${NODE_IP}:8265']
    metrics_path: '/metrics'
EOF

# Set proper permissions
chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Restart Prometheus
echo "[configure_monitoring] Restarting Prometheus..."
systemctl restart prometheus

# Wait for Prometheus to be ready
sleep 3

# Configure Grafana with Prometheus datasource and default dashboards
echo "[configure_monitoring] Configuring Grafana..."

# Get Grafana admin credentials (now from common config)
# GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASS are set in 00_setup_common.sh

# Wait for Grafana to be fully up
echo "[configure_monitoring] Waiting for Grafana to be ready..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GRAFANA_PORT}/api/health" | grep -q "200"; then
    echo "[configure_monitoring] Grafana is ready"
    break
  fi
  sleep 1
done

# Create Prometheus datasource in Grafana
echo "[configure_monitoring] Adding Prometheus datasource to Grafana..."
cat > /tmp/grafana-datasource.json << EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "access": "proxy",
  "url": "http://localhost:9090",
  "isDefault": true,
  "jsonData": {
    "timeInterval": "15s"
  }
}
EOF

# Add datasource via Grafana API
curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" \
  -d @/tmp/grafana-datasource.json \
  "http://localhost:${GRAFANA_PORT}/api/datasources" | grep -q "datasource created" && echo "✓ Prometheus datasource added" || echo "⚠ Datasource may already exist"

# Create a basic Ray dashboard
echo "[configure_monitoring] Creating basic Ray dashboard..."
cat > /tmp/ray-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "Ray Cluster Dashboard",
    "tags": ["ray", "cluster"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Ray CPU Usage",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "ray_actors_num{State=\"ALIVE\"}",
            "refId": "A",
            "legendFormat": "Alive Actors"
          }
        ],
        "yaxes": [
          {"format": "short", "label": "Count"},
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"}
      },
      {
        "id": 2,
        "title": "Ray Node Count",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "ray_cluster_resources_cpu",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 1},
                {"color": "red", "value": 10}
              ]
            },
            "unit": "short"
          }
        }
      },
      {
        "id": 3,
        "title": "Ray GPU Usage",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
        "targets": [
          {
            "expr": "ray_cluster_resources_GPU",
            "refId": "A",
            "legendFormat": "GPU Count"
          }
        ],
        "yaxes": [
          {"format": "short", "label": "GPU Count"},
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"}
      }
    ],
    "refresh": "10s",
    "time": {
      "from": "now-1h",
      "to": "now"
    }
  },
  "folderId": null,
  "overwrite": false
}
EOF

# Import dashboard via Grafana API
DASHBOARD_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" \
  -d @/tmp/ray-dashboard.json \
  "http://localhost:${GRAFANA_PORT}/api/dashboards/db")

if echo "$DASHBOARD_RESPONSE" | grep -q '"status":"success"'; then
  echo "✓ Ray dashboard created successfully"
else
  echo "⚠ Dashboard may already exist or creation failed"
  echo "$DASHBOARD_RESPONSE" | grep -o '"message":"[^"]*"' || true
fi

# Cleanup temp files
rm -f /tmp/grafana-datasource.json /tmp/ray-dashboard.json

# Check service status
echo "[configure_monitoring] Checking service status..."
if systemctl is-active --quiet prometheus; then
  echo "[configure_monitoring] ✓ Prometheus is running"
else
  echo "[configure_monitoring] ✗ Prometheus is not running"
  systemctl status prometheus --no-pager | head -10
fi

if systemctl is-active --quiet grafana-server; then
  echo "[configure_monitoring] ✓ Grafana is running"
else
  echo "[configure_monitoring] ✗ Grafana is not running"
  systemctl status grafana-server --no-pager | head -10
fi

echo "[configure_monitoring] Done"
echo ""
echo "[configure_monitoring] Monitoring configuration complete:"
echo "[configure_monitoring] - Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[configure_monitoring] - Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "[configure_monitoring] - Default Grafana credentials: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS}"

