#!/bin/bash
#===============================================================================
# Node Exporter Uninstallation Script
# Part of the observability-stack module system
#
# Usage:
#   ./uninstall.sh [--purge]
#===============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_warn() { echo "[WARN] $1"; }
fi

# Configuration
SERVICE_NAME="node_exporter"
BINARY_PATH="/usr/local/bin/node_exporter"
USER_NAME="node_exporter"
GROUP_NAME="node_exporter"

PURGE_DATA=false
for arg in "$@"; do
    case "$arg" in
        --purge)
            PURGE_DATA=true
            ;;
    esac
done

#===============================================================================
# UNINSTALL
#===============================================================================

main() {
    log_info "Uninstalling Node Exporter..."

    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    fi
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    # Remove service file
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload

    # Remove binary
    rm -f "$BINARY_PATH"

    # Remove user and group
    userdel "$USER_NAME" 2>/dev/null || true
    groupdel "$GROUP_NAME" 2>/dev/null || true

    log_success "Node Exporter uninstalled"
}

main "$@"
