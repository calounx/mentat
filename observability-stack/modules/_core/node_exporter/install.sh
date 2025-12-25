#!/bin/bash
#===============================================================================
# Node Exporter Installation Script
# Part of the observability-stack module system
#
# Environment variables expected:
#   MODULE_NAME    - Name of the module (node_exporter)
#   MODULE_DIR     - Path to the module directory
#   MODULE_VERSION - Version to install
#   MODULE_PORT    - Port the exporter listens on
#   FORCE_MODE     - Set to "true" to force reinstall
#   OBSERVABILITY_IP - IP address of the observability VPS (for firewall)
#
# Usage:
#   ./install.sh [--force]
#===============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    # Minimal fallback if common.sh not available
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_skip() { echo "[SKIP] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# Module configuration
MODULE_NAME="${MODULE_NAME:-node_exporter}"
MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
MODULE_PORT="${MODULE_PORT:-9100}"
FORCE_MODE="${FORCE_MODE:-false}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

# Installation paths
BINARY_NAME="node_exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="node_exporter"
USER_NAME="node_exporter"
GROUP_NAME="node_exporter"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_MODE=true
            ;;
    esac
done

#===============================================================================
# VERSION CHECK
#===============================================================================

is_installed() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -x "$INSTALL_PATH" ]]; then
        return 1
    fi

    local current_version
    current_version=$("$INSTALL_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$current_version" == "$MODULE_VERSION" ]]; then
        return 0
    fi
    return 1
}

#===============================================================================
# INSTALLATION
#===============================================================================

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."

    cd /tmp

    # Download
    local archive_name="node_exporter-${MODULE_VERSION}.linux-amd64.tar.gz"
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${MODULE_VERSION}/${archive_name}"

    log_info "Downloading from $download_url..."
    wget -q "$download_url" -O "$archive_name"

    # Extract
    tar xzf "$archive_name"

    # Install binary
    cp "node_exporter-${MODULE_VERSION}.linux-amd64/node_exporter" "$INSTALL_PATH"
    chown "$USER_NAME:$GROUP_NAME" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    # Cleanup
    rm -rf "node_exporter-${MODULE_VERSION}.linux-amd64" "$archive_name"

    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
}

create_service() {
    log_info "Creating systemd service..."

    # Build flags from host configuration if available
    local extra_flags=""
    if [[ -n "${HOST_CONFIG_FLAGS:-}" ]]; then
        extra_flags="$HOST_CONFIG_FLAGS"
    fi

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
Wants=network-online.target
After=network-online.target

[Service]
User=$USER_NAME
Group=$GROUP_NAME
Type=simple
ExecStart=$INSTALL_PATH \\
    --collector.systemd \\
    --collector.processes $extra_flags

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

configure_firewall() {
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        log_warn "OBSERVABILITY_IP not set, skipping firewall configuration"
        return
    fi

    if command -v ufw &>/dev/null; then
        if ! ufw status | grep -q "$OBSERVABILITY_IP.*$MODULE_PORT"; then
            log_info "Configuring firewall..."
            ufw allow from "$OBSERVABILITY_IP" to any port "$MODULE_PORT" proto tcp
        fi
    fi
}

start_service() {
    log_info "Starting $SERVICE_NAME..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Verify it's running
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$MODULE_NAME running (port $MODULE_PORT)"
    else
        log_error "$MODULE_NAME failed to start"
        systemctl status "$SERVICE_NAME" --no-pager
        return 1
    fi
}

verify_metrics() {
    log_info "Verifying metrics endpoint..."

    if curl -sf "http://localhost:$MODULE_PORT/metrics" | grep -q "node_cpu_seconds_total"; then
        log_success "Metrics endpoint verified"
    else
        log_warn "Could not verify metrics endpoint"
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    # Stop existing service before any changes
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_info "Stopping existing $SERVICE_NAME..."
        systemctl stop "$SERVICE_NAME"
        sleep 1
    fi
    pkill -f "$INSTALL_PATH" 2>/dev/null || true
    sleep 1

    # Create user
    create_user

    # Check if already installed
    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"
    else
        install_binary
    fi

    # Always ensure service is configured
    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        create_service
    fi

    # Configure firewall
    configure_firewall

    # Start service
    start_service

    # Verify
    verify_metrics
}

main "$@"
