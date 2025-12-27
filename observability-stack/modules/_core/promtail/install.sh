#!/bin/bash
#===============================================================================
# Promtail Installation and Upgrade Script
# Phase 3: Promtail 2.9.3 -> 3.6.3 Upgrade System
#
# DEPRECATION NOTICE:
#   Promtail has been deprecated in favor of Grafana Alloy.
#   End-of-Life: March 2, 2026
#   LTS Support Until: February 28, 2026
#
# Features:
#   - Configuration migration support
#   - Version matching with Loki
#   - Position file preservation
#   - Health checks and rollback
#   - Future Alloy migration path notes
#
# Risk Level: MEDIUM
# Estimated Downtime: 1-2 minutes per host
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

# Source common library
if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_skip() { echo "[SKIP] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# CONFIGURATION
#===============================================================================

MODULE_NAME="${MODULE_NAME:-promtail}"
MODULE_VERSION="${MODULE_VERSION:-3.6.3}"
MODULE_PORT="${MODULE_PORT:-9080}"
FORCE_MODE="${FORCE_MODE:-false}"

# Promtail-specific config (must be provided)
LOKI_URL="${LOKI_URL:-}"
LOKI_USER="${LOKI_USER:-}"
LOKI_PASS="${LOKI_PASS:-}"

BINARY_NAME="promtail"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="promtail"
USER_NAME="promtail"
CONFIG_DIR="/etc/promtail"
DATA_DIR="/var/lib/promtail"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/observability-upgrades/backups/promtail}"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE_MODE=true ;;
    esac
done

#===============================================================================
# DEPRECATION WARNING
#===============================================================================

print_deprecation_warning() {
    echo ""
    echo "========================================================================"
    echo "  DEPRECATION NOTICE: Promtail"
    echo "========================================================================"
    echo ""
    echo "  Promtail has been deprecated in favor of Grafana Alloy."
    echo ""
    echo "  Key Dates:"
    echo "    - LTS Support Until: February 28, 2026"
    echo "    - End-of-Life: March 2, 2026"
    echo "    - Security Patches: Available until EOL"
    echo ""
    echo "  Why Upgrade to 3.6.3 Despite Deprecation?"
    echo "    1. Security fixes until EOL (13+ months of support)"
    echo "    2. Compatibility with Loki 3.6.3"
    echo "    3. Synchronized version matching"
    echo "    4. Maintained stability during Alloy migration planning"
    echo ""
    echo "  Migration Timeline:"
    echo "    - Q1 2025: Upgrade to Promtail 3.6.3 (this upgrade)"
    echo "    - Q2 2025: Plan and test Alloy migration in staging"
    echo "    - Q3 2025: Execute Alloy rollout"
    echo "    - Q4 2025: Complete migration before EOL"
    echo ""
    echo "  Alloy Migration Command (for future use):"
    echo "    alloy convert --source-format=promtail \\"
    echo "      --output=/etc/alloy/config.alloy \\"
    echo "      /etc/promtail/promtail.yaml"
    echo ""
    echo "  Documentation:"
    echo "    - Migration Guide: https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/"
    echo "    - Alloy Docs: https://grafana.com/docs/alloy/latest/"
    echo ""
    echo "========================================================================"
    echo ""
}

#===============================================================================
# VERSION DETECTION
#===============================================================================

# Get currently installed version
get_installed_version() {
    if [[ -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
    else
        echo ""
    fi
}

# Check if upgrade is needed
is_installed() {
    [[ "$FORCE_MODE" == "true" ]] && return 1
    [[ ! -x "$INSTALL_PATH" ]] && return 1
    local current_version
    current_version=$(get_installed_version)
    [[ "$current_version" == "$MODULE_VERSION" ]]
}

# Determine if this is a major version upgrade
is_major_upgrade() {
    local current_version
    current_version=$(get_installed_version)

    if [[ -z "$current_version" ]]; then
        return 1  # New installation
    fi

    local current_major="${current_version%%.*}"
    local target_major="${MODULE_VERSION%%.*}"

    [[ "$current_major" != "$target_major" ]]
}

# Check Loki version compatibility
check_loki_compatibility() {
    log_info "Checking Loki version compatibility..."

    # Try to get Loki version from local endpoint
    local loki_version=""

    if [[ -n "$LOKI_URL" ]]; then
        local loki_metrics
        loki_metrics=$(curl -sf "${LOKI_URL}/metrics" 2>/dev/null || echo "")

        if [[ -n "$loki_metrics" ]]; then
            loki_version=$(echo "$loki_metrics" | grep "loki_build_info" | \
                grep -oP 'version="[^"]*"' | cut -d'"' -f2)
        fi
    fi

    # Also check localhost if Loki is local
    if [[ -z "$loki_version" ]]; then
        loki_metrics=$(curl -sf "http://localhost:3100/metrics" 2>/dev/null || echo "")
        if [[ -n "$loki_metrics" ]]; then
            loki_version=$(echo "$loki_metrics" | grep "loki_build_info" | \
                grep -oP 'version="[^"]*"' | cut -d'"' -f2)
        fi
    fi

    if [[ -n "$loki_version" ]]; then
        local loki_major="${loki_version%%.*}"
        local promtail_major="${MODULE_VERSION%%.*}"

        if [[ "$loki_major" != "$promtail_major" ]]; then
            log_warn "Version mismatch: Loki $loki_version, Promtail $MODULE_VERSION"
            log_warn "Recommendation: Upgrade Loki FIRST, then Promtail"
            return 1
        else
            log_info "Version compatibility OK: Loki $loki_version, Promtail $MODULE_VERSION"
        fi
    else
        log_warn "Could not detect Loki version - ensure Loki is upgraded first"
    fi

    return 0
}

#===============================================================================
# BACKUP OPERATIONS
#===============================================================================

# Create backup before upgrade
backup_promtail() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname
    hostname=$(hostname)
    local backup_path="$BACKUP_DIR/$hostname/$timestamp"

    log_info "Creating backup at $backup_path..."
    mkdir -p "$backup_path"
    chmod 700 "$backup_path"

    # Backup binary
    if [[ -f "$INSTALL_PATH" ]]; then
        local current_version
        current_version=$(get_installed_version)
        cp -p "$INSTALL_PATH" "$backup_path/promtail-${current_version}"
        log_info "Backed up binary: promtail-${current_version}"
    fi

    # Backup configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -rp "$CONFIG_DIR" "$backup_path/config"
        log_info "Backed up configuration"
    fi

    # Backup positions file (CRITICAL - tracks log reading progress)
    if [[ -f "$DATA_DIR/positions.yaml" ]]; then
        cp -p "$DATA_DIR/positions.yaml" "$backup_path/"
        log_info "Backed up positions file"
    fi

    # Backup systemd service
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        cp -p "/etc/systemd/system/${SERVICE_NAME}.service" "$backup_path/"
        log_info "Backed up service file"
    fi

    # Create backup metadata
    cat > "$backup_path/metadata.json" <<EOF
{
  "component": "promtail",
  "hostname": "$hostname",
  "timestamp": "$timestamp",
  "version": "$(get_installed_version)",
  "target_version": "$MODULE_VERSION",
  "created_by": "promtail-upgrade"
}
EOF

    log_success "Backup created: $backup_path"
    echo "$backup_path"
}

# Restore from backup
restore_from_backup() {
    local backup_path="$1"

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi

    log_info "Restoring from backup: $backup_path"

    # Stop service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    # Restore binary
    local binary_backup
    binary_backup=$(ls "$backup_path"/promtail-* 2>/dev/null | head -1)
    if [[ -f "$binary_backup" ]]; then
        cp -p "$binary_backup" "$INSTALL_PATH"
        chown root:root "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
        log_info "Restored binary"
    fi

    # Restore configuration
    if [[ -d "$backup_path/config" ]]; then
        rm -rf "$CONFIG_DIR"
        cp -rp "$backup_path/config" "$CONFIG_DIR"
        chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR"
        log_info "Restored configuration"
    fi

    # Restore positions file
    if [[ -f "$backup_path/positions.yaml" ]]; then
        cp -p "$backup_path/positions.yaml" "$DATA_DIR/"
        chown "$USER_NAME:$USER_NAME" "$DATA_DIR/positions.yaml"
        log_info "Restored positions file"
    fi

    # Restore service file
    if [[ -f "$backup_path/${SERVICE_NAME}.service" ]]; then
        cp -p "$backup_path/${SERVICE_NAME}.service" "/etc/systemd/system/"
        systemctl daemon-reload
        log_info "Restored service file"
    fi

    # Start service
    systemctl start "$SERVICE_NAME"

    log_success "Restore completed"
    return 0
}

#===============================================================================
# INSTALLATION
#===============================================================================

# Create system user
create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi

    # Add to groups for log access
    usermod -a -G adm "$USER_NAME"
    usermod -a -G www-data "$USER_NAME" 2>/dev/null || true

    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR" "$DATA_DIR"
}

# Download and install binary
install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    local archive_name="promtail-linux-amd64.zip"
    local download_url="https://github.com/grafana/loki/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/grafana/loki/releases/download/v${MODULE_VERSION}/SHA256SUMS"

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for Promtail"
        log_error "Refusing to install unverified binary"
        return 1
    fi

    unzip -o "$archive_name"
    chmod +x "promtail-linux-amd64"

    # Verify binary works
    if ! ./promtail-linux-amd64 -version &>/dev/null; then
        log_error "Downloaded binary failed version check"
        return 1
    fi

    # Install binary
    mv "promtail-linux-amd64" "$INSTALL_PATH"
    chown root:root "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    # Cleanup
    rm -f "$archive_name" SHA256SUMS

    log_success "$MODULE_NAME binary installed"
}

# Create or update configuration
create_config() {
    if [[ -z "$LOKI_URL" ]]; then
        log_warn "LOKI_URL not provided, skipping config creation"
        return 1
    fi

    # Normalize LOKI_URL
    LOKI_URL="${LOKI_URL%/}"
    LOKI_URL="${LOKI_URL%/loki}"
    LOKI_URL="${LOKI_URL%/}"

    local HOSTNAME
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)

    log_info "Creating Promtail configuration..."
    cat > "$CONFIG_DIR/promtail.yaml" << EOF
# Promtail Configuration
# Version: $MODULE_VERSION
# Generated: $(date -Iseconds)
#
# DEPRECATION NOTICE: Promtail EOL March 2, 2026
# Migration target: Grafana Alloy
# Convert command: alloy convert --source-format=promtail

server:
  http_listen_port: $MODULE_PORT
  grpc_listen_port: 0

positions:
  filename: $DATA_DIR/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    basic_auth:
      username: ${LOKI_USER}
      password: ${LOKI_PASS}
    # Backoff configuration for reliability
    backoff_config:
      min_period: 500ms
      max_period: 5m
      max_retries: 10

scrape_configs:
  - job_name: nginx_access
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx_access
          host: ${HOSTNAME}
          __path__: /var/log/nginx/access.log

  - job_name: nginx_error
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx_error
          host: ${HOSTNAME}
          __path__: /var/log/nginx/error.log

  - job_name: php_error
    static_configs:
      - targets: [localhost]
        labels:
          job: php_error
          host: ${HOSTNAME}
          __path__: /var/log/php*-fpm.log

  - job_name: mysql_slow
    static_configs:
      - targets: [localhost]
        labels:
          job: mysql_slow
          host: ${HOSTNAME}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s

  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log

  - job_name: wordpress
    static_configs:
      - targets: [localhost]
        labels:
          job: wordpress
          host: ${HOSTNAME}
          __path__: /var/www/*/wp-content/debug.log
EOF

    chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR/promtail.yaml"
    chmod 640 "$CONFIG_DIR/promtail.yaml"

    log_success "Promtail configuration created"
}

# Validate configuration
validate_config() {
    log_info "Validating Promtail configuration..."

    local config_file="$CONFIG_DIR/promtail.yaml"

    if [[ ! -f "$config_file" ]]; then
        log_warn "No configuration file found"
        return 0
    fi

    # Check YAML syntax
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            log_error "Configuration file has invalid YAML syntax"
            return 1
        fi
    fi

    # Check label count (Loki 3.4+ enforces 15 label limit)
    local label_count
    label_count=$(grep -c "__path__:" "$config_file" 2>/dev/null || echo "0")

    # Check for excessive static labels per job
    local max_labels=0
    while read -r line; do
        if [[ "$line" =~ labels: ]]; then
            local job_labels=0
            while read -r label_line; do
                if [[ "$label_line" =~ ^[[:space:]]*[a-z_]+: ]]; then
                    ((job_labels++))
                elif [[ "$label_line" =~ ^[[:space:]]*- ]]; then
                    break
                fi
            done
            if [[ $job_labels -gt $max_labels ]]; then
                max_labels=$job_labels
            fi
        fi
    done < "$config_file"

    if [[ $max_labels -gt 10 ]]; then
        log_warn "High label count detected: $max_labels labels"
        log_warn "Loki 3.4+ enforces 15 label limit per series"
        log_warn "Consider reducing labels or using structured metadata"
    fi

    log_success "Configuration validation passed"
    return 0
}

# Create systemd service
create_service() {
    log_info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=Promtail Log Shipping Agent
Documentation=https://grafana.com/docs/loki/latest/send-data/promtail/
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
ExecReload=/bin/kill -HUP $MAINPID

# SECURITY: Systemd hardening
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/var/lib/promtail /etc/promtail
ReadOnlyPaths=/var/log /var/www
PrivateTmp=true
NoNewPrivileges=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_DAC_READ_SEARCH
RestrictNamespaces=true
LockPersonality=true

# Resource limits
LimitNOFILE=65536

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

#===============================================================================
# HEALTH CHECKS
#===============================================================================

# Wait for Promtail to become ready
wait_for_ready() {
    local max_attempts="${1:-30}"
    local attempt=1

    log_info "Waiting for Promtail to become ready..."

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
            log_success "Promtail is ready"
            return 0
        fi

        log_info "Waiting for Promtail... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_error "Promtail failed to become ready after $max_attempts attempts"
    return 1
}

# Verify Promtail health
verify_health() {
    log_info "Verifying Promtail health..."

    # Check ready endpoint
    if ! curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
        log_error "Promtail /ready endpoint failed"
        return 1
    fi

    # Check metrics endpoint
    local metrics
    metrics=$(curl -sf "http://localhost:${MODULE_PORT}/metrics" 2>/dev/null)

    if [[ -z "$metrics" ]]; then
        log_error "Promtail /metrics endpoint failed"
        return 1
    fi

    # Check for active targets
    local targets
    targets=$(curl -sf "http://localhost:${MODULE_PORT}/targets" 2>/dev/null)

    if [[ -n "$targets" ]]; then
        local active_targets
        active_targets=$(echo "$targets" | grep -c '"state": "Running"' || echo "0")
        log_info "Active scrape targets: $active_targets"
    fi

    # Check log shipping
    local sent_entries
    sent_entries=$(echo "$metrics" | grep "promtail_sent_entries_total" | head -1 || echo "")

    if [[ -n "$sent_entries" ]]; then
        log_info "Log shipping metrics: $sent_entries"
    fi

    log_success "Promtail health verification passed"
    return 0
}

#===============================================================================
# START/STOP OPERATIONS
#===============================================================================

start_service() {
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$MODULE_NAME running (log shipping to Loki)"
    else
        log_error "$MODULE_NAME failed to start"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager
        return 1
    fi

    # Wait for ready
    wait_for_ready 30 || return 1

    return 0
}

stop_service() {
    log_info "Stopping $SERVICE_NAME service..."

    # H-7: Add service stop verification before binary replacement
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"

        # Wait for process to actually stop with timeout
        local wait_count=0
        local max_wait=30
        while pgrep -f "$INSTALL_PATH" >/dev/null 2>&1 && [[ $wait_count -lt $max_wait ]]; do
            log_info "Waiting for $SERVICE_NAME to stop... ($wait_count/$max_wait)"
            sleep 1
            ((wait_count++))
        done

        if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
            log_warn "Service did not stop gracefully, sending SIGKILL"
            pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true
            sleep 2
        fi
    fi

    pkill -f "$INSTALL_PATH" 2>/dev/null || true
    sleep 1

    log_info "$SERVICE_NAME stopped"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    # Print deprecation warning for major upgrades
    local current_version
    current_version=$(get_installed_version)

    if is_major_upgrade || [[ -z "$current_version" ]]; then
        print_deprecation_warning
    fi

    log_info "=========================================="
    log_info "Promtail Installation/Upgrade Script"
    log_info "Target version: $MODULE_VERSION"
    log_info "=========================================="

    if [[ -n "$current_version" ]]; then
        log_info "Current version: $current_version"

        if is_major_upgrade; then
            log_warn "MAJOR VERSION UPGRADE: $current_version -> $MODULE_VERSION"
        fi
    else
        log_info "New installation"
    fi

    # Check Loki version compatibility
    check_loki_compatibility || log_warn "Proceeding despite version mismatch warning"

    # Validate existing configuration
    validate_config || true

    # Check if already at target version
    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"
        return 0
    fi

    # Stop service before upgrade
    stop_service

    # Create backup before upgrade
    local backup_path=""
    if [[ -n "$current_version" ]]; then
        backup_path=$(backup_promtail)
        export BACKUP_PATH="$backup_path"
    fi

    # Create user and directories
    create_user

    # Install binary
    if ! install_binary; then
        log_error "Binary installation failed"

        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" || log_error "Rollback failed"
        fi
        return 1
    fi

    # Create/update configuration
    create_config || true

    # Create or update service file
    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        create_service
    fi

    # Start service
    if [[ -f "$CONFIG_DIR/promtail.yaml" ]]; then
        if ! start_service; then
            log_error "Service failed to start"

            if [[ -n "$backup_path" ]]; then
                log_warn "Attempting rollback..."
                restore_from_backup "$backup_path" && log_success "Rollback successful"
            fi
            return 1
        fi

        # Verify health
        if ! verify_health; then
            log_error "Health verification failed"

            if [[ -n "$backup_path" ]]; then
                log_warn "Attempting rollback..."
                restore_from_backup "$backup_path" && log_success "Rollback successful"
            fi
            return 1
        fi
    else
        log_warn "Promtail installed but not started (no config)"
    fi

    # Success
    local new_version
    new_version=$(get_installed_version)

    log_success "=========================================="
    log_success "Promtail upgrade completed successfully!"
    if [[ -n "$current_version" ]]; then
        log_success "Version: $current_version -> $new_version"
    else
        log_success "Version: $new_version (new install)"
    fi
    if [[ -n "$backup_path" ]]; then
        log_info "Backup available at: $backup_path"
    fi
    log_success "=========================================="

    # Final deprecation reminder
    echo ""
    log_warn "REMINDER: Promtail is deprecated (EOL: March 2, 2026)"
    log_warn "Plan migration to Grafana Alloy before EOL"
    log_warn "See: https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/"
    echo ""

    return 0
}

main "$@"
