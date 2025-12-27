#!/bin/bash
#===============================================================================
# Component Upgrade Script
# Part of the observability-stack upgrade orchestration system
#
# Performs atomic upgrade of a single component with idempotency guarantees
#
# Environment Variables Required:
#   MODULE_NAME     - Component name (e.g., "node_exporter")
#   MODULE_VERSION  - Target version (e.g., "1.9.1")
#   BACKUP_PATH     - Path to backup directory (optional)
#
# Exit Codes:
#   0 - Success
#   1 - Failure (with rollback if possible)
#   2 - Already upgraded (idempotent skip)
#
# Usage:
#   MODULE_NAME=node_exporter MODULE_VERSION=1.9.1 ./upgrade-component.sh
#===============================================================================

set -euo pipefail

#===============================================================================
# SETUP
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/versions.sh"

# Required environment variables
MODULE_NAME="${MODULE_NAME:-}"
MODULE_VERSION="${MODULE_VERSION:-}"
BACKUP_PATH="${BACKUP_PATH:-}"

if [[ -z "$MODULE_NAME" ]]; then
    log_fatal "MODULE_NAME environment variable required"
fi

if [[ -z "$MODULE_VERSION" ]]; then
    log_fatal "MODULE_VERSION environment variable required"
fi

# P0-2: Check for required external dependencies
check_dependencies() {
    local missing=()
    for cmd in jq curl python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fatal "Missing required dependencies: ${missing[*]}"
    fi
}

# Verify dependencies before proceeding
check_dependencies

log_info "Component Upgrade: $MODULE_NAME -> $MODULE_VERSION"

#===============================================================================
# MODULE DISCOVERY
#===============================================================================

# Find module directory
MODULE_DIR=""
for search_path in \
    "$STACK_ROOT/modules/_core/$MODULE_NAME" \
    "$STACK_ROOT/modules/$MODULE_NAME" \
    "$STACK_ROOT/modules/custom/$MODULE_NAME"; do

    if [[ -d "$search_path" ]]; then
        MODULE_DIR="$search_path"
        break
    fi
done

if [[ -z "$MODULE_DIR" ]]; then
    log_fatal "Module directory not found for: $MODULE_NAME"
fi

log_debug "Module directory: $MODULE_DIR"

#===============================================================================
# IDEMPOTENCY CHECK
#===============================================================================

# Check if already installed at target version
BINARY_PATH="/usr/local/bin/$MODULE_NAME"

if [[ -x "$BINARY_PATH" ]]; then
    CURRENT_VERSION=$("$BINARY_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")

    if [[ "$CURRENT_VERSION" == "$MODULE_VERSION" ]]; then
        log_success "Component $MODULE_NAME already at version $MODULE_VERSION (idempotent skip)"
        exit 2
    fi

    log_info "Current version: $CURRENT_VERSION, upgrading to: $MODULE_VERSION"
else
    log_info "Component $MODULE_NAME not currently installed"
    CURRENT_VERSION="not_installed"
fi

#===============================================================================
# PRE-UPGRADE CHECKS
#===============================================================================

log_info "Running pre-upgrade checks..."

# Check if module has install script
INSTALL_SCRIPT="$MODULE_DIR/install.sh"

if [[ ! -x "$INSTALL_SCRIPT" ]]; then
    log_fatal "Install script not found or not executable: $INSTALL_SCRIPT"
fi

# Check disk space (minimum 500MB)
AVAILABLE_SPACE=$(df /var/lib 2>/dev/null | tail -1 | awk '{print $4}')
MIN_SPACE=512000  # 500MB in KB

if [[ $AVAILABLE_SPACE -lt $MIN_SPACE ]]; then
    log_fatal "Insufficient disk space: ${AVAILABLE_SPACE}KB available, ${MIN_SPACE}KB required"
fi

log_success "Pre-upgrade checks passed"

#===============================================================================
# SERVICE MANAGEMENT
#===============================================================================

SERVICE_NAME="${MODULE_NAME}"
SERVICE_WAS_RUNNING=false

# Check if service exists and is running
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Service $SERVICE_NAME is running, will restart after upgrade"
        SERVICE_WAS_RUNNING=true
    fi
fi

#===============================================================================
# EXECUTE UPGRADE
#===============================================================================

log_info "Executing upgrade installation..."

# Stop service if running
if [[ "$SERVICE_WAS_RUNNING" == "true" ]]; then
    log_info "Stopping service: $SERVICE_NAME"
    systemctl stop "$SERVICE_NAME" || {
        log_warn "Failed to stop service cleanly, continuing..."
    }
    sleep 2
fi

# Run module installation with specific version
export MODULE_VERSION
export FORCE_MODE="true"  # Force reinstall even if version matches

if ! "$INSTALL_SCRIPT"; then
    log_error "Installation script failed"

    # Attempt to restart service if it was running
    if [[ "$SERVICE_WAS_RUNNING" == "true" ]]; then
        log_info "Attempting to restart service after failed upgrade..."
        systemctl start "$SERVICE_NAME" || log_error "Failed to restart service"
    fi

    exit 1
fi

log_success "Installation completed"

#===============================================================================
# POST-UPGRADE VERIFICATION
#===============================================================================

log_info "Verifying upgrade..."

# Verify binary was installed
if [[ ! -x "$BINARY_PATH" ]]; then
    log_error "Binary not found after installation: $BINARY_PATH"
    exit 1
fi

# Verify version
INSTALLED_VERSION=$("$BINARY_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")

if [[ "$INSTALLED_VERSION" != "$MODULE_VERSION" ]]; then
    log_error "Version mismatch after installation"
    log_error "Expected: $MODULE_VERSION"
    log_error "Got: $INSTALLED_VERSION"
    exit 1
fi

log_success "Binary verified: $MODULE_NAME v$INSTALLED_VERSION"

#===============================================================================
# SERVICE RESTART
#===============================================================================

# Restart service if it was running
if [[ "$SERVICE_WAS_RUNNING" == "true" ]]; then
    log_info "Restarting service: $SERVICE_NAME"

    # Reload systemd in case service file changed
    systemctl daemon-reload

    if ! systemctl start "$SERVICE_NAME"; then
        log_error "Failed to start service after upgrade"

        # Show service status for debugging
        systemctl status "$SERVICE_NAME" --no-pager || true

        exit 1
    fi

    # Wait for service to be fully started
    sleep 3

    # Verify service is running
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "Service failed to start properly"
        systemctl status "$SERVICE_NAME" --no-pager || true
        exit 1
    fi

    log_success "Service restarted successfully"
fi

#===============================================================================
# FINAL CHECKS
#===============================================================================

# If this is an exporter, verify metrics endpoint
if [[ "$MODULE_NAME" == *"exporter"* ]]; then
    # Determine port based on component
    case "$MODULE_NAME" in
        node_exporter)
            METRICS_PORT=9100
            ;;
        nginx_exporter)
            METRICS_PORT=9113
            ;;
        mysqld_exporter)
            METRICS_PORT=9104
            ;;
        phpfpm_exporter)
            METRICS_PORT=9253
            ;;
        fail2ban_exporter)
            METRICS_PORT=9191
            ;;
        *)
            METRICS_PORT=""
            ;;
    esac

    if [[ -n "$METRICS_PORT" ]]; then
        log_info "Verifying metrics endpoint on port $METRICS_PORT..."

        # Wait up to 30 seconds for metrics endpoint
        ATTEMPTS=0
        MAX_ATTEMPTS=6

        while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
            if curl -s "http://localhost:${METRICS_PORT}/metrics" > /dev/null 2>&1; then
                log_success "Metrics endpoint responding"
                break
            fi

            log_debug "Waiting for metrics endpoint (attempt $((ATTEMPTS + 1))/$MAX_ATTEMPTS)..."
            sleep 5
            ((ATTEMPTS++))
        done

        if [[ $ATTEMPTS -eq $MAX_ATTEMPTS ]]; then
            log_warn "Metrics endpoint not responding (non-fatal)"
        fi
    fi
fi

#===============================================================================
# CLEANUP
#===============================================================================

# Clean up temporary files if any
cd /tmp
rm -f "${MODULE_NAME}-${MODULE_VERSION}".* 2>/dev/null || true

#===============================================================================
# SUCCESS
#===============================================================================

log_success "===== Component upgrade successful: $MODULE_NAME $CURRENT_VERSION -> $MODULE_VERSION ====="

exit 0
