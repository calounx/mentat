#!/bin/bash
# ============================================================================
# Deploy Monitoring Agents on Monitored Nodes
# Non-interactive wrapper that sources libraries and runs monitored role
#
# This script installs monitoring exporters and telemetry collectors on nodes
# that should be monitored by the central observability stack.
#
# Supports:
#   - Grafana Alloy (default) - Modern unified telemetry collector
#   - Promtail (legacy) - Log shipping only
#
# Usage:
#   OBSERVABILITY_IP=10.10.100.10 HOST_NAME=myserver HOST_IP=10.10.100.20 ./deploy-monitored.sh
#
# Environment Variables:
#   HOST_NAME          - Name of this host (required)
#   HOST_IP            - IP address of this host (required)
#   OBSERVABILITY_IP   - IP of the central observability server (required)
#   TELEMETRY_COLLECTOR - "alloy" (default) or "promtail"
#   APP_ENV            - Environment label: "production", "test", etc.
# ============================================================================
set -euo pipefail

LOG_PREFIX="[DEPLOY-MONITORED]"
STACK_PATH="/opt/observability-stack"
DEPLOY_DIR="$STACK_PATH/deploy"

echo "$LOG_PREFIX Starting monitored node deployment..."
echo "$LOG_PREFIX Using Grafana Alloy as default telemetry collector"
echo ""

# Wait for systemd to be fully ready (allow degraded since some services may fail initially)
max_wait=60
waited=0
while true; do
    status=$(systemctl is-system-running 2>/dev/null || echo "unknown")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        echo "$LOG_PREFIX Systemd is ready (status: $status)"
        break
    fi
    if [[ $waited -ge $max_wait ]]; then
        echo "$LOG_PREFIX WARNING: Systemd not fully ready after ${max_wait}s, proceeding anyway..."
        break
    fi
    echo "$LOG_PREFIX Waiting for systemd... (status: $status)"
    sleep 2
    waited=$((waited + 2))
done

# Check if deployment scripts exist
if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "$LOG_PREFIX ERROR: observability-stack not mounted at $STACK_PATH"
    echo "$LOG_PREFIX Please ensure the observability-stack is available at $STACK_PATH"
    exit 1
fi

# Set STACK_DIR for the deployment scripts
export STACK_DIR="$STACK_PATH"

# The observability-stack may be mounted read-only, so use a writable location for generated configs
export CONFIG_DIR="/etc/observability-stack"
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

echo "$LOG_PREFIX Using writable config directory: $CONFIG_DIR"

# Source the required libraries
echo "$LOG_PREFIX Loading deployment libraries..."
source "$DEPLOY_DIR/lib/common.sh"

# Validate required configuration
if [[ -z "${HOST_NAME:-}" ]]; then
    echo "$LOG_PREFIX ERROR: HOST_NAME is required"
    echo "$LOG_PREFIX Example: HOST_NAME=landsraad_tst ./deploy-monitored.sh"
    exit 1
fi

if [[ -z "${HOST_IP:-}" ]]; then
    echo "$LOG_PREFIX ERROR: HOST_IP is required"
    echo "$LOG_PREFIX Example: HOST_IP=10.10.100.20 ./deploy-monitored.sh"
    exit 1
fi

if [[ -z "${OBSERVABILITY_IP:-}" ]]; then
    echo "$LOG_PREFIX ERROR: OBSERVABILITY_IP is required"
    echo "$LOG_PREFIX Example: OBSERVABILITY_IP=10.10.100.10 ./deploy-monitored.sh"
    exit 1
fi

# Set non-interactive configuration variables
export HOST_NAME="${HOST_NAME}"
export HOST_IP="${HOST_IP}"
export OBSERVABILITY_IP="${OBSERVABILITY_IP}"

# Telemetry collector choice: alloy (recommended) or promtail (legacy)
# Alloy is the modern unified collector replacing Promtail
export TELEMETRY_COLLECTOR="${TELEMETRY_COLLECTOR:-alloy}"

# Environment configuration
export APP_ENV="${APP_ENV:-production}"

# Auto-detect test environment from hostname
if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]] || [[ "${HOST_NAME}" == *"_test"* ]]; then
    export APP_ENV="${APP_ENV:-test}"
fi

# Standard exporter ports (matching production)
readonly NODE_EXPORTER_PORT=9100
readonly NGINX_EXPORTER_PORT=9113
readonly MYSQLD_EXPORTER_PORT=9104
readonly PHPFPM_EXPORTER_PORT=9253
readonly FAIL2BAN_EXPORTER_PORT=9191
readonly PROMTAIL_PORT=9080
readonly ALLOY_PORT=12345

echo "$LOG_PREFIX Configuration:"
echo "  HOST_NAME:          $HOST_NAME"
echo "  HOST_IP:            $HOST_IP"
echo "  OBSERVABILITY_IP:   $OBSERVABILITY_IP"
echo "  APP_ENV:            $APP_ENV"
echo "  TELEMETRY_COLLECTOR: $TELEMETRY_COLLECTOR"
echo ""

# Source the monitored role script (this defines the functions)
echo "$LOG_PREFIX Loading monitored role..."
source "$DEPLOY_DIR/roles/monitored.sh"

# Run the main installation function
echo "$LOG_PREFIX Running monitored host installation..."
install_monitored_host

# Print deployment summary
echo ""
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Monitored node deployment complete!"
echo "$LOG_PREFIX ========================================"
echo ""
echo "$LOG_PREFIX Monitoring Endpoints (monitored-* job naming):"
echo "  - Node Exporter:    http://${HOST_IP}:${NODE_EXPORTER_PORT}/metrics"

# Print detected service endpoints
for svc in "${DETECTED_SERVICES[@]:-}"; do
    case "$svc" in
        nginx_exporter)
            echo "  - Nginx Exporter:   http://${HOST_IP}:${NGINX_EXPORTER_PORT}/metrics"
            ;;
        mysqld_exporter)
            echo "  - MySQL Exporter:   http://${HOST_IP}:${MYSQLD_EXPORTER_PORT}/metrics"
            ;;
        phpfpm_exporter)
            echo "  - PHP-FPM Exporter: http://${HOST_IP}:${PHPFPM_EXPORTER_PORT}/metrics"
            ;;
        fail2ban_exporter)
            echo "  - Fail2ban Exporter: http://${HOST_IP}:${FAIL2BAN_EXPORTER_PORT}/metrics"
            ;;
    esac
done

# Print telemetry collector info
echo ""
echo "$LOG_PREFIX Telemetry Collector:"
case "${TELEMETRY_COLLECTOR,,}" in
    alloy)
        echo "  - Alloy:            Shipping logs to ${OBSERVABILITY_IP}:3100 (port ${ALLOY_PORT})"
        echo "  - Alloy UI:         http://${HOST_IP}:${ALLOY_PORT}"
        ;;
    *)
        echo "  - Promtail:         Shipping logs to ${OBSERVABILITY_IP}:3100 (port ${PROMTAIL_PORT})"
        ;;
esac

echo ""
echo "$LOG_PREFIX Prometheus Target File:"
echo "  - Local:  /tmp/${HOST_NAME}-targets.yaml"
echo "  - Remote: Copy to observability VPS with:"
echo ""
echo "    scp /tmp/${HOST_NAME}-targets.yaml root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
echo ""
echo "$LOG_PREFIX After copying, Prometheus will auto-discover this node within 30 seconds."
echo ""
