#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00_setup_common.sh"

echo "[install_monitoring] Installing Prometheus and Grafana..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "[install_monitoring] ⚠ This script needs root privileges to install or configure system services."
  if systemctl is-active --quiet prometheus 2>/dev/null && systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo "[install_monitoring] ✓ Prometheus and Grafana already appear to be running. Skipping installation."
    exit 0
  fi
  echo "[install_monitoring] Skipping automatic installation. If installation is required, run:"
  echo "[install_monitoring]   sudo bash $0"
  exit 0
fi

# Detect distribution
if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  DISTRIB_ID="$ID"
else
  echo "[install_monitoring] ERROR: Cannot detect distribution" >&2
  exit 1
fi

echo "[install_monitoring] Detected distribution: $DISTRIB_ID"

# Install Prometheus
if ! command -v prometheus >/dev/null 2>&1; then
  echo "[install_monitoring] Installing Prometheus..."
  
  case "$DISTRIB_ID" in
    ubuntu|debian)
      # Download Prometheus binary
      PROM_VERSION="3.7.3"
      ARCH="linux-amd64"
      PROM_FILE="prometheus-${PROM_VERSION}.${ARCH}.tar.gz"
      PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_FILE}"
      
      cd /tmp
      wget -q "$PROM_URL" -O "$PROM_FILE"
      tar xzf "$PROM_FILE"
      
      # Install binary and create systemd service
      cp "prometheus-${PROM_VERSION}.${ARCH}/prometheus" /usr/local/bin/
      cp "prometheus-${PROM_VERSION}.${ARCH}/promtool" /usr/local/bin/
      chmod +x /usr/local/bin/prometheus
      chmod +x /usr/local/bin/promtool
      
      # Create directories
      mkdir -p /etc/prometheus
      mkdir -p /var/lib/prometheus
      
      # Create basic Prometheus configuration
      cat > /etc/prometheus/prometheus.yml << 'PROMCONFIG'
# Prometheus configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Scrape Prometheus itself
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMCONFIG
      
      # Create systemd service
      cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF
      
      # Create prometheus user
      useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
      chown -R prometheus:prometheus /etc/prometheus
      chown -R prometheus:prometheus /var/lib/prometheus
      
      # Cleanup
      rm -rf "/tmp/prometheus-${PROM_VERSION}.${ARCH}" "/tmp/${PROM_FILE}"
      ;;
    
    *)
      echo "[install_monitoring] ERROR: Unsupported distribution: $DISTRIB_ID" >&2
      exit 1
      ;;
  esac
  
  echo "[install_monitoring] Prometheus installed successfully"
else
  echo "[install_monitoring] Prometheus already installed"
  
  # Check if config file exists, create if missing
  if [[ ! -f /etc/prometheus/prometheus.yml ]]; then
    echo "[install_monitoring] Creating missing Prometheus config file..."
    cat > /etc/prometheus/prometheus.yml << 'PROMCONFIG'
# Prometheus configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Scrape Prometheus itself
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMCONFIG
    chown prometheus:prometheus /etc/prometheus/prometheus.yml 2>/dev/null || true
    echo "[install_monitoring] ✓ Prometheus config created"
  fi
fi

# Install Grafana
if ! command -v grafana-server >/dev/null 2>&1; then
  echo "[install_monitoring] Installing Grafana..."
  
  case "$DISTRIB_ID" in
    ubuntu|debian)
      # Install Grafana via apt repository
      apt-get update -qq
      apt-get install -y -qq software-properties-common apt-transport-https ca-certificates gnupg
      
      # Add Grafana GPG key (modern method without apt-key)
      mkdir -p /etc/apt/keyrings
      wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
      chmod 644 /etc/apt/keyrings/grafana.gpg
      
      # Add Grafana repository
      echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
      
      apt-get update -qq
      apt-get install -y -qq grafana
      
      # Enable Grafana to start on boot
      systemctl enable grafana-server
      ;;
    
    *)
      echo "[install_monitoring] ERROR: Unsupported distribution: $DISTRIB_ID" >&2
      exit 1
      ;;
  esac
  
  echo "[install_monitoring] Grafana installed successfully"
else
  echo "[install_monitoring] Grafana already installed"
fi

# Start services
echo "[install_monitoring] Starting Prometheus service..."
systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus || true

echo "[install_monitoring] Starting Grafana service..."
systemctl restart grafana-server || true

# Wait for services to be ready
echo "[install_monitoring] Waiting for services to be ready..."
sleep 5

# Check if services are running
if systemctl is-active --quiet prometheus; then
  echo "[install_monitoring] ✓ Prometheus is running"
else
  echo "[install_monitoring] ⚠ Prometheus service status: $(systemctl is-active prometheus || echo unknown)"
fi

if systemctl is-active --quiet grafana-server; then
  echo "[install_monitoring] ✓ Grafana is running"
else
  echo "[install_monitoring] ⚠ Grafana service status: $(systemctl is-active grafana-server || echo unknown)"
fi

echo "[install_monitoring] Done"
echo ""
echo "[install_monitoring] Next steps:"
NODE_IP="${NODE_IP:-$(primary_ip)}"
echo "[install_monitoring] - Prometheus UI: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "[install_monitoring] - Grafana UI: http://${NODE_IP}:${GRAFANA_PORT} (default login: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})"

