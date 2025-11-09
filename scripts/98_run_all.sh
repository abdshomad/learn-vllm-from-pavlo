#!/usr/bin/env bash
set -euo pipefail

# Master script to run all setup and deployment scripts in sequence
# All output is logged to a single datetime-stamped file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source global environment defaults if present
ENV_FILE="${REPO_ROOT}/env.sh"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# Ensure PATH includes common uv installation locations
export PATH="$HOME/.local/bin:/root/.local/bin:/usr/local/bin:$PATH"

# Create logs directory if it doesn't exist
LOG_DIR_NOTE=""
LOGS_DIR="${REPO_ROOT}/logs"
mkdir -p "$LOGS_DIR" 2>/dev/null || true

# Fallback if the default logs directory is not writable (e.g., owned by root)
if [[ ! -w "$LOGS_DIR" ]]; then
    ALT_LOGS_DIR="${REPO_ROOT}/logs-local"
    mkdir -p "$ALT_LOGS_DIR"
    if [[ -w "$ALT_LOGS_DIR" ]]; then
        LOGS_DIR="$ALT_LOGS_DIR"
    else
        LOGS_DIR="$(mktemp -d "/tmp/run_all_logs_XXXX")"
    fi
    LOG_DIR_NOTE="Using alternate logs directory: $LOGS_DIR (default logs/ not writable)"
fi

# Generate datetime-stamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOGS_DIR}/run_all_${TIMESTAMP}.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to run a script with logging
run_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${script_name}"
    local description="${2:-$script_name}"
    
    if [[ ! -f "$script_path" ]]; then
        log_with_timestamp "${RED}[ERROR]${NC} Script not found: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        log_with_timestamp "${YELLOW}[WARN]${NC} Making script executable: $script_path"
        chmod +x "$script_path"
    fi
    
    log_with_timestamp "${GREEN}[START]${NC} Running: $description"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "Running: $description" | tee -a "$LOG_FILE"
    echo "Script: $script_path" | tee -a "$LOG_FILE"
    echo "Started at: $(date)" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    
    # Run the script, capturing both stdout and stderr
    # Ensure PATH is exported for the script
    if env PATH="$PATH" bash "$script_path" >> "$LOG_FILE" 2>&1; then
        echo "========================================" | tee -a "$LOG_FILE"
        echo "Completed: $description" | tee -a "$LOG_FILE"
        echo "Finished at: $(date)" | tee -a "$LOG_FILE"
        echo "========================================" | tee -a "$LOG_FILE"
        log_with_timestamp "${GREEN}[SUCCESS]${NC} Completed: $description"
        return 0
    else
        local exit_code=$?
        echo "========================================" | tee -a "$LOG_FILE"
        echo "FAILED: $description" | tee -a "$LOG_FILE"
        echo "Exit code: $exit_code" | tee -a "$LOG_FILE"
        echo "Finished at: $(date)" | tee -a "$LOG_FILE"
        echo "========================================" | tee -a "$LOG_FILE"
        log_with_timestamp "${RED}[ERROR]${NC} Failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Main execution
log_with_timestamp "${GREEN}========================================${NC}"
log_with_timestamp "${GREEN}Starting full deployment pipeline${NC}"
log_with_timestamp "${GREEN}Log file: $LOG_FILE${NC}"
if [[ -n "$LOG_DIR_NOTE" ]]; then
    log_with_timestamp "${YELLOW}[WARN]${NC} ${LOG_DIR_NOTE}"
fi
log_with_timestamp "${GREEN}========================================${NC}"

# Track which scripts succeed/fail
FAILED_SCRIPTS=()
SUCCESSFUL_SCRIPTS=()

# Core setup scripts
run_script "01_setup_venv.sh" "Setup virtual environment" && SUCCESSFUL_SCRIPTS+=("01_setup_venv.sh") || FAILED_SCRIPTS+=("01_setup_venv.sh")

run_script "02_prepare_shared.sh" "Prepare shared storage directory" && SUCCESSFUL_SCRIPTS+=("02_prepare_shared.sh") || FAILED_SCRIPTS+=("02_prepare_shared.sh")

run_script "03_download_tinyllama.sh" "Download TinyLlama model" && SUCCESSFUL_SCRIPTS+=("03_download_tinyllama.sh") || FAILED_SCRIPTS+=("03_download_tinyllama.sh")

# Monitoring setup (optional - continue even if it fails)
run_script "03a_install_monitoring.sh" "Install monitoring tools (Prometheus/Grafana)" && SUCCESSFUL_SCRIPTS+=("03a_install_monitoring.sh") || {
    FAILED_SCRIPTS+=("03a_install_monitoring.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Monitoring installation failed, continuing..."
}

# Ray cluster setup
run_script "04_start_ray_head.sh" "Start Ray head node" && SUCCESSFUL_SCRIPTS+=("04_start_ray_head.sh") || {
    FAILED_SCRIPTS+=("04_start_ray_head.sh")
    log_with_timestamp "${RED}[ERROR]${NC} Ray head failed to start. Cannot continue with Ray-dependent scripts."
    log_with_timestamp "${RED}[ERROR]${NC} Please check the logs and fix Ray startup before retrying."
}

# Ray worker (optional - skip if not needed)
if [[ "${RUN_WORKER:-false}" == "true" ]]; then
    run_script "05_start_ray_worker.sh" "Start Ray worker node" && SUCCESSFUL_SCRIPTS+=("05_start_ray_worker.sh") || {
        FAILED_SCRIPTS+=("05_start_ray_worker.sh")
        log_with_timestamp "${YELLOW}[WARN]${NC} Ray worker failed, continuing with head node only..."
    }
fi

# Monitoring configuration (optional - continue even if it fails)
run_script "05a_configure_monitoring.sh" "Configure monitoring" && SUCCESSFUL_SCRIPTS+=("05a_configure_monitoring.sh") || {
    FAILED_SCRIPTS+=("05a_configure_monitoring.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Monitoring configuration failed, continuing..."
}

run_script "05b_verify_monitoring.sh" "Verify monitoring setup" && SUCCESSFUL_SCRIPTS+=("05b_verify_monitoring.sh") || {
    FAILED_SCRIPTS+=("05b_verify_monitoring.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Monitoring verification failed, continuing..."
}

# Prometheus fixes (optional - continue even if they fail)
run_script "05c_fix_prometheus_config.sh" "Fix Prometheus configuration" && SUCCESSFUL_SCRIPTS+=("05c_fix_prometheus_config.sh") || {
    FAILED_SCRIPTS+=("05c_fix_prometheus_config.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Prometheus config fix failed, continuing..."
}

run_script "05d_verify_prometheus_config.sh" "Verify Prometheus configuration" && SUCCESSFUL_SCRIPTS+=("05d_verify_prometheus_config.sh") || {
    FAILED_SCRIPTS+=("05d_verify_prometheus_config.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Prometheus verification failed, continuing..."
}

run_script "05e_fix_ray_dashboard_no_data.sh" "Fix Ray dashboard data issues" && SUCCESSFUL_SCRIPTS+=("05e_fix_ray_dashboard_no_data.sh") || {
    FAILED_SCRIPTS+=("05e_fix_ray_dashboard_no_data.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Ray dashboard fix failed, continuing..."
}

# vLLM deployment (choose one: single node or Ray)
if [[ "${USE_RAY_VLLM:-false}" == "true" ]]; then
    run_script "07_launch_vllm_ray.sh" "Launch vLLM with Ray backend" && SUCCESSFUL_SCRIPTS+=("07_launch_vllm_ray.sh") || {
        FAILED_SCRIPTS+=("07_launch_vllm_ray.sh")
        log_with_timestamp "${RED}[ERROR]${NC} vLLM Ray deployment failed"
    }
else
    run_script "06_launch_vllm_single_node.sh" "Launch vLLM single node" && SUCCESSFUL_SCRIPTS+=("06_launch_vllm_single_node.sh") || {
        FAILED_SCRIPTS+=("06_launch_vllm_single_node.sh")
        log_with_timestamp "${RED}[ERROR]${NC} vLLM single node deployment failed"
    }
fi

# vLLM tests (only if vLLM is running)
if [[ ! " ${FAILED_SCRIPTS[@]} " =~ " 06_launch_vllm_single_node.sh " ]] && [[ ! " ${FAILED_SCRIPTS[@]} " =~ " 07_launch_vllm_ray.sh " ]]; then
    run_script "08z_vllm_run_all.sh" "Run all vLLM tests" && SUCCESSFUL_SCRIPTS+=("08z_vllm_run_all.sh") || {
        FAILED_SCRIPTS+=("08z_vllm_run_all.sh")
        log_with_timestamp "${YELLOW}[WARN]${NC} Some vLLM tests failed"
    }
fi

# Ray Serve deployment
run_script "09_deploy_ray_serve.sh" "Deploy Ray Serve application" && SUCCESSFUL_SCRIPTS+=("09_deploy_ray_serve.sh") || {
    FAILED_SCRIPTS+=("09_deploy_ray_serve.sh")
    log_with_timestamp "${YELLOW}[WARN]${NC} Ray Serve deployment failed"
}

# Output service URLs for convenience
if [[ -f "$REPO_ROOT/env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/env.sh"
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/00_setup_common.sh"

# Collect primary node IP (best effort)
PRIMARY_IP="${NODE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

log_with_timestamp ""
log_with_timestamp "${GREEN}Service URLs:${NC}"
log_with_timestamp "  Ray Dashboard:      http://${PRIMARY_IP:-localhost}:${RAY_PORT:-8265}"
log_with_timestamp "  Ray Serve Ingress:  http://${PRIMARY_IP:-localhost}:${SERVE_PORT:-8001}/"
if [[ -n "${VLLM_PORT:-}" ]]; then
    log_with_timestamp "  vLLM API:           http://${PRIMARY_IP:-localhost}:${VLLM_PORT}"
fi
log_with_timestamp "  Prometheus:         http://${PRIMARY_IP:-localhost}:${PROMETHEUS_PORT:-9090}"
log_with_timestamp "  Grafana:            http://${PRIMARY_IP:-localhost}:${GRAFANA_PORT:-3000}"
# Summary
log_with_timestamp "${GREEN}========================================${NC}"
log_with_timestamp "${GREEN}Deployment pipeline completed${NC}"
log_with_timestamp "${GREEN}========================================${NC}"
log_with_timestamp "Total scripts run: $((${#SUCCESSFUL_SCRIPTS[@]} + ${#FAILED_SCRIPTS[@]}))"
log_with_timestamp "${GREEN}Successful: ${#SUCCESSFUL_SCRIPTS[@]}${NC}"
log_with_timestamp "${RED}Failed: ${#FAILED_SCRIPTS[@]}${NC}"

if [[ ${#SUCCESSFUL_SCRIPTS[@]} -gt 0 ]]; then
    log_with_timestamp "${GREEN}Successful scripts:${NC}"
    for script in "${SUCCESSFUL_SCRIPTS[@]}"; do
        log_with_timestamp "  ✓ $script"
    done
fi

if [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
    log_with_timestamp "${RED}Failed scripts:${NC}"
    for script in "${FAILED_SCRIPTS[@]}"; do
        log_with_timestamp "  ✗ $script"
    done
fi

log_with_timestamp ""
log_with_timestamp "Full log available at: $LOG_FILE"
log_with_timestamp ""

# Exit with error if any critical scripts failed
CRITICAL_SCRIPTS=("01_setup_venv.sh" "02_prepare_shared.sh" "03_download_tinyllama.sh" "04_start_ray_head.sh")
CRITICAL_FAILED=false

for script in "${CRITICAL_SCRIPTS[@]}"; do
    if [[ " ${FAILED_SCRIPTS[@]} " =~ " $script " ]]; then
        CRITICAL_FAILED=true
        break
    fi
done

if [[ "$CRITICAL_FAILED" == "true" ]]; then
    log_with_timestamp "${RED}[ERROR]${NC} One or more critical scripts failed. Please review the log file."
    exit 1
elif [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
    log_with_timestamp "${YELLOW}[WARN]${NC} Some non-critical scripts failed, but deployment may still be functional."
    exit 0
else
    log_with_timestamp "${GREEN}[SUCCESS]${NC} All scripts completed successfully!"
    exit 0
fi

