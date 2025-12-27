#!/bin/bash
#===============================================================================
# Prometheus Installation and Two-Stage Upgrade Script
# Part of the observability-stack module system
#
# Supports two-stage upgrade path for major version migrations:
#   Stage 1: 2.48.1 -> 2.55.1 (TSDB v1 -> v2 migration)
#   Stage 2: 2.55.1 -> 3.8.1  (TSDB v2 -> v3 + breaking changes)
#
# Environment variables expected:
#   MODULE_NAME       - Name of the module (prometheus)
#   MODULE_DIR        - Path to the module directory
#   MODULE_VERSION    - Version to install (auto-detected for upgrades)
#   FORCE_MODE        - Set to "true" to force reinstall
#   PROMETHEUS_DATA   - Data directory (default: /var/lib/prometheus)
#   PROMETHEUS_CONFIG - Config directory (default: /etc/prometheus)
#   SKIP_BACKUP       - Set to "true" to skip TSDB backup (not recommended)
#   UPGRADE_STAGE     - Force specific upgrade stage (1 or 2)
#
# Usage:
#   ./install.sh [--force] [--upgrade] [--stage=1|2] [--dry-run]
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
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $1"; }
fi

# Source versions library for version comparison
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
fi

#===============================================================================
# MODULE CONFIGURATION
#===============================================================================

MODULE_NAME="${MODULE_NAME:-prometheus}"
FORCE_MODE="${FORCE_MODE:-false}"
DRY_RUN="${DRY_RUN:-false}"
UPGRADE_MODE="${UPGRADE_MODE:-false}"
UPGRADE_STAGE="${UPGRADE_STAGE:-auto}"

# Installation paths
BINARY_NAME="prometheus"
PROMTOOL_NAME="promtool"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
PROMTOOL_PATH="/usr/local/bin/$PROMTOOL_NAME"
SERVICE_NAME="prometheus"
USER_NAME="prometheus"
GROUP_NAME="prometheus"

# Data and config paths
PROMETHEUS_DATA="${PROMETHEUS_DATA:-/var/lib/prometheus}"
PROMETHEUS_CONFIG="${PROMETHEUS_CONFIG:-/etc/prometheus}"
PROMETHEUS_LOG="${PROMETHEUS_LOG:-/var/log/prometheus}"

# Backup configuration
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/lib/observability-upgrades/backups/prometheus}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"

# Two-stage upgrade versions
VERSION_CURRENT="2.48.1"
VERSION_INTERMEDIATE="2.55.1"
VERSION_TARGET="3.8.1"

# Port configuration
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_MODE=true
            ;;
        --upgrade)
            UPGRADE_MODE=true
            ;;
        --stage=*)
            UPGRADE_STAGE="${arg#*=}"
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            ;;
    esac
done

#===============================================================================
# VERSION DETECTION AND COMPARISON
#===============================================================================

# Detect currently installed Prometheus version
detect_current_version() {
    if [[ ! -x "$INSTALL_PATH" ]]; then
        echo ""
        return 1
    fi

    local version
    version=$("$INSTALL_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "$version"
}

# Get major version number
get_major_version() {
    local version="$1"
    echo "$version" | cut -d. -f1
}

# Get minor version number
get_minor_version() {
    local version="$1"
    echo "$version" | cut -d. -f2
}

# Compare semantic versions (returns -1, 0, or 1)
# Usage: version_cmp "1.0.0" "2.0.0" -> -1
version_cmp() {
    local v1="$1"
    local v2="$2"

    # Use versions.sh compare_versions if available
    if type compare_versions &>/dev/null; then
        compare_versions "$v1" "$v2"
        return 0
    fi

    # Fallback implementation
    local IFS=.
    local i v1_parts=($v1) v2_parts=($v2)

    for ((i=0; i<${#v1_parts[@]} || i<${#v2_parts[@]}; i++)); do
        local n1=${v1_parts[i]:-0}
        local n2=${v2_parts[i]:-0}

        if ((n1 > n2)); then
            echo 1
            return 0
        elif ((n1 < n2)); then
            echo -1
            return 0
        fi
    done

    echo 0
}

# Determine which upgrade stage is needed
determine_upgrade_stage() {
    local current_version="$1"
    local target_version="${2:-$VERSION_TARGET}"

    if [[ -z "$current_version" ]]; then
        log_info "No current version detected, fresh install"
        echo "fresh"
        return 0
    fi

    local current_major
    current_major=$(get_major_version "$current_version")

    # Version < 2.55.1 needs stage 1
    local cmp_intermediate
    cmp_intermediate=$(version_cmp "$current_version" "$VERSION_INTERMEDIATE")

    if [[ $cmp_intermediate -eq -1 ]]; then
        echo "stage1"
        return 0
    fi

    # Version >= 2.55.1 but < 3.0 needs stage 2
    local cmp_target
    cmp_target=$(version_cmp "$current_version" "$VERSION_TARGET")

    if [[ $current_major -eq 2 && $cmp_target -eq -1 ]]; then
        echo "stage2"
        return 0
    fi

    # Already at or past target
    if [[ $cmp_target -ge 0 ]]; then
        echo "current"
        return 0
    fi

    echo "unknown"
}

#===============================================================================
# TSDB BACKUP FUNCTIONS
#===============================================================================

# Create TSDB snapshot using Prometheus API
create_tsdb_snapshot() {
    local snapshot_name="pre-upgrade-$(date +%Y%m%d_%H%M%S)"

    log_info "Creating TSDB snapshot via API..."

    # Check if admin API is enabled
    if ! curl -sf "http://localhost:${PROMETHEUS_PORT}/-/healthy" &>/dev/null; then
        log_warn "Prometheus not accessible, cannot create API snapshot"
        return 1
    fi

    # Trigger snapshot creation
    local snapshot_response
    if snapshot_response=$(curl -sf -X POST "http://localhost:${PROMETHEUS_PORT}/api/v1/admin/tsdb/snapshot" 2>&1); then
        local snapshot_path
        snapshot_path=$(echo "$snapshot_response" | grep -oP '"name"\s*:\s*"\K[^"]+' || true)

        if [[ -n "$snapshot_path" ]]; then
            log_success "TSDB snapshot created: $snapshot_path"
            echo "${PROMETHEUS_DATA}/snapshots/${snapshot_path}"
            return 0
        fi
    fi

    log_warn "Failed to create TSDB snapshot via API (admin API may be disabled)"
    return 1
}

# Create file-based backup of TSDB
backup_tsdb_files() {
    local backup_dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    log_info "Creating file-based TSDB backup..."

    # Stop Prometheus for consistent backup
    local was_running=false
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        was_running=true
        log_info "Stopping Prometheus for consistent backup..."
        systemctl stop "$SERVICE_NAME"
        sleep 5
    fi

    # Create backup directory
    local tsdb_backup_dir="${backup_dir}/tsdb-${timestamp}"
    mkdir -p "$tsdb_backup_dir"

    # Copy TSDB data
    if [[ -d "$PROMETHEUS_DATA" ]]; then
        log_info "Backing up TSDB data from $PROMETHEUS_DATA..."

        # Calculate size
        local data_size
        data_size=$(du -sh "$PROMETHEUS_DATA" 2>/dev/null | cut -f1)
        log_info "TSDB data size: $data_size"

        # Copy with progress
        if command -v rsync &>/dev/null; then
            rsync -a --info=progress2 "$PROMETHEUS_DATA/" "$tsdb_backup_dir/data/"
        else
            cp -a "$PROMETHEUS_DATA" "$tsdb_backup_dir/data"
        fi

        log_success "TSDB data backed up to $tsdb_backup_dir"
    else
        log_warn "TSDB data directory not found: $PROMETHEUS_DATA"
    fi

    # Restart Prometheus if it was running
    if [[ "$was_running" == "true" ]]; then
        log_info "Restarting Prometheus..."
        systemctl start "$SERVICE_NAME"
    fi

    echo "$tsdb_backup_dir"
}

# Backup configuration files
backup_config() {
    local backup_dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    log_info "Backing up configuration..."

    local config_backup_dir="${backup_dir}/config-${timestamp}"
    mkdir -p "$config_backup_dir"

    # Backup config directory
    if [[ -d "$PROMETHEUS_CONFIG" ]]; then
        cp -a "$PROMETHEUS_CONFIG" "$config_backup_dir/etc-prometheus"
        log_success "Config backed up to $config_backup_dir"
    fi

    # Backup systemd service
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        cp "/etc/systemd/system/${SERVICE_NAME}.service" "$config_backup_dir/"
    fi

    # Backup binaries
    if [[ -x "$INSTALL_PATH" ]]; then
        cp "$INSTALL_PATH" "$config_backup_dir/"
    fi
    if [[ -x "$PROMTOOL_PATH" ]]; then
        cp "$PROMTOOL_PATH" "$config_backup_dir/"
    fi

    echo "$config_backup_dir"
}

# Full pre-upgrade backup
create_full_backup() {
    local stage="$1"
    local current_version="$2"

    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log_warn "SKIP_BACKUP is set - skipping backup (NOT RECOMMENDED for production)"
        return 0
    fi

    log_info "Creating full pre-upgrade backup for stage $stage..."

    local backup_dir="${BACKUP_BASE_DIR}/${stage}-${current_version}-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    # Create backup metadata
    cat > "$backup_dir/metadata.json" <<EOF
{
    "component": "prometheus",
    "stage": "$stage",
    "from_version": "$current_version",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_type": "full",
    "created_by": "prometheus-upgrade-script"
}
EOF

    # Backup config
    local config_backup
    config_backup=$(backup_config "$backup_dir")

    # Try API snapshot first, fallback to file backup
    local tsdb_backup=""
    if ! tsdb_backup=$(create_tsdb_snapshot); then
        tsdb_backup=$(backup_tsdb_files "$backup_dir")
    fi

    # Update metadata with backup paths
    cat > "$backup_dir/metadata.json" <<EOF
{
    "component": "prometheus",
    "stage": "$stage",
    "from_version": "$current_version",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_type": "full",
    "config_backup": "$config_backup",
    "tsdb_backup": "$tsdb_backup",
    "created_by": "prometheus-upgrade-script"
}
EOF

    log_success "Full backup created: $backup_dir"
    echo "$backup_dir"
}

#===============================================================================
# CONFIG VALIDATION AND MIGRATION
#===============================================================================

# Validate Prometheus configuration
validate_config() {
    local config_file="${PROMETHEUS_CONFIG}/prometheus.yml"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        return 1
    fi

    log_info "Validating Prometheus configuration..."

    # Use promtool if available
    if [[ -x "$PROMTOOL_PATH" ]]; then
        if "$PROMTOOL_PATH" check config "$config_file" 2>&1; then
            log_success "Configuration validation passed"
            return 0
        else
            log_error "Configuration validation failed"
            return 1
        fi
    else
        log_warn "promtool not available, skipping config validation"
        return 0
    fi
}

# Check for deprecated flags in service file
check_deprecated_flags() {
    local target_version="$1"
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    local issues=()

    if [[ ! -f "$service_file" ]]; then
        log_warn "Service file not found: $service_file"
        return 0
    fi

    log_info "Checking for deprecated flags..."

    local target_major
    target_major=$(get_major_version "$target_version")

    # Flags deprecated/removed in Prometheus 3.x
    if [[ $target_major -ge 3 ]]; then
        # Flags removed in 3.x
        local removed_flags=(
            "--storage.tsdb.no-lockfile"
            "--storage.tsdb.allow-overlapping-blocks"
        )

        for flag in "${removed_flags[@]}"; do
            if grep -q "$flag" "$service_file"; then
                issues+=("REMOVED FLAG: $flag - must be removed before upgrade to 3.x")
            fi
        done

        # Flags renamed in 3.x
        if grep -q "--storage.tsdb.wal-compression" "$service_file" && \
           ! grep -q "--storage.tsdb.wal-compression-type" "$service_file"; then
            issues+=("RENAMED FLAG: --storage.tsdb.wal-compression -> --storage.tsdb.wal-compression-type=zstd")
        fi
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "Found deprecated/removed flags that need attention:"
        for issue in "${issues[@]}"; do
            log_warn "  - $issue"
        done
        return 1
    fi

    log_success "No deprecated flags found"
    return 0
}

# Migrate service configuration for 3.x
migrate_service_config() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    if [[ ! -f "$service_file" ]]; then
        return 0
    fi

    log_info "Migrating service configuration for 3.x compatibility..."

    # Create backup
    cp "$service_file" "${service_file}.pre-3x-backup"

    # Remove deprecated flags
    sed -i 's/--storage\.tsdb\.no-lockfile//g' "$service_file"
    sed -i 's/--storage\.tsdb\.allow-overlapping-blocks//g' "$service_file"

    # Rename flags
    sed -i 's/--storage\.tsdb\.wal-compression\b/--storage.tsdb.wal-compression-type=zstd/g' "$service_file"

    # Clean up any double spaces or trailing backslashes
    sed -i 's/  */ /g' "$service_file"
    sed -i 's/ \\$/\\/g' "$service_file"

    systemctl daemon-reload

    log_success "Service configuration migrated"
}

#===============================================================================
# TSDB HEALTH CHECKS
#===============================================================================

# Check TSDB health
check_tsdb_health() {
    log_info "Checking TSDB health..."

    # Check if data directory exists
    if [[ ! -d "$PROMETHEUS_DATA" ]]; then
        log_warn "TSDB data directory not found: $PROMETHEUS_DATA"
        return 0
    fi

    # Check for WAL corruption indicators
    local wal_dir="${PROMETHEUS_DATA}/wal"
    if [[ -d "$wal_dir" ]]; then
        local wal_files
        wal_files=$(find "$wal_dir" -type f 2>/dev/null | wc -l)
        log_info "WAL directory contains $wal_files files"
    fi

    # Use promtool for TSDB analysis if available
    if [[ -x "$PROMTOOL_PATH" ]]; then
        log_info "Running TSDB analysis with promtool..."
        if "$PROMTOOL_PATH" tsdb analyze "$PROMETHEUS_DATA" 2>&1 | head -20; then
            log_success "TSDB analysis completed"
        fi
    fi

    # Check for lock file
    if [[ -f "${PROMETHEUS_DATA}/lock" ]]; then
        log_warn "TSDB lock file exists - ensure Prometheus is stopped before upgrade"
    fi

    return 0
}

# Monitor TSDB migration progress
monitor_tsdb_migration() {
    local max_wait="${1:-300}"  # 5 minutes default
    local check_interval=10

    log_info "Monitoring TSDB migration progress..."

    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        # Check if Prometheus is up
        if curl -sf "http://localhost:${PROMETHEUS_PORT}/-/ready" &>/dev/null; then
            log_success "Prometheus is ready after TSDB migration"
            return 0
        fi

        # Check service status
        if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            log_error "Prometheus service stopped during migration"
            journalctl -u "$SERVICE_NAME" -n 50 --no-pager
            return 1
        fi

        log_info "Waiting for TSDB migration to complete... (${elapsed}s / ${max_wait}s)"
        sleep $check_interval
        ((elapsed += check_interval))
    done

    log_error "TSDB migration timeout after ${max_wait}s"
    return 1
}

#===============================================================================
# BINARY INSTALLATION
#===============================================================================

# Create prometheus user
create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
}

# Download and install Prometheus binary
install_binary() {
    local version="$1"

    log_info "Installing Prometheus v$version..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Prometheus v$version"
        return 0
    fi

    cd /tmp

    local archive_name="prometheus-${version}.linux-amd64.tar.gz"
    local download_url="https://github.com/prometheus/prometheus/releases/download/v${version}/${archive_name}"
    local checksum_url="https://github.com/prometheus/prometheus/releases/download/v${version}/sha256sums.txt"

    # SECURITY: Download with checksum verification
    if type download_and_verify &>/dev/null; then
        if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
            log_error "SECURITY: Failed to download and verify $archive_name"
            return 1
        fi
    else
        log_warn "SECURITY: download_and_verify not available, downloading without verification"
        if ! wget -q --timeout=60 --tries=3 "$download_url" -O "$archive_name"; then
            log_error "Failed to download Prometheus from $download_url"
            return 1
        fi
    fi

    # Extract
    if ! tar xzf "$archive_name"; then
        log_error "Failed to extract $archive_name"
        rm -f "$archive_name"
        return 1
    fi

    local extract_dir="prometheus-${version}.linux-amd64"

    # Stop service before replacing binary
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_info "Stopping Prometheus service..."
        systemctl stop "$SERVICE_NAME"
        sleep 3
    fi

    # Install binaries
    if ! cp "${extract_dir}/prometheus" "$INSTALL_PATH"; then
        log_error "Failed to install prometheus binary"
        rm -rf "$extract_dir" "$archive_name"
        return 1
    fi

    if ! cp "${extract_dir}/promtool" "$PROMTOOL_PATH"; then
        log_error "Failed to install promtool binary"
        rm -rf "$extract_dir" "$archive_name"
        return 1
    fi

    # Set permissions
    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        safe_chown "root:root" "$INSTALL_PATH"
        safe_chown "root:root" "$PROMTOOL_PATH"
        safe_chmod 755 "$INSTALL_PATH" "prometheus binary"
        safe_chmod 755 "$PROMTOOL_PATH" "promtool binary"
    else
        chown root:root "$INSTALL_PATH" "$PROMTOOL_PATH"
        chmod 755 "$INSTALL_PATH" "$PROMTOOL_PATH"
    fi

    # Install console templates if first install
    if [[ ! -d "${PROMETHEUS_CONFIG}/consoles" ]]; then
        mkdir -p "${PROMETHEUS_CONFIG}/consoles"
        cp -r "${extract_dir}/consoles"/* "${PROMETHEUS_CONFIG}/consoles/" 2>/dev/null || true
    fi
    if [[ ! -d "${PROMETHEUS_CONFIG}/console_libraries" ]]; then
        mkdir -p "${PROMETHEUS_CONFIG}/console_libraries"
        cp -r "${extract_dir}/console_libraries"/* "${PROMETHEUS_CONFIG}/console_libraries/" 2>/dev/null || true
    fi

    # Cleanup
    rm -rf "$extract_dir" "$archive_name"

    log_success "Prometheus v$version installed"
}

# Create systemd service file
create_service() {
    local version="$1"

    log_info "Creating systemd service..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create systemd service"
        return 0
    fi

    local major_version
    major_version=$(get_major_version "$version")

    # Build ExecStart with appropriate flags
    local exec_start="$INSTALL_PATH \\
    --config.file=${PROMETHEUS_CONFIG}/prometheus.yml \\
    --storage.tsdb.path=${PROMETHEUS_DATA} \\
    --web.console.templates=${PROMETHEUS_CONFIG}/consoles \\
    --web.console.libraries=${PROMETHEUS_CONFIG}/console_libraries \\
    --web.listen-address=:${PROMETHEUS_PORT} \\
    --web.enable-lifecycle"

    # Add version-specific flags
    if [[ $major_version -ge 3 ]]; then
        # Prometheus 3.x flags
        exec_start="$exec_start \\
    --storage.tsdb.wal-compression-type=zstd"
    else
        # Prometheus 2.x flags
        exec_start="$exec_start \\
    --storage.tsdb.wal-compression"
    fi

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
User=$USER_NAME
Group=$GROUP_NAME
Type=simple
ExecStart=$exec_start
ExecReload=/bin/kill -HUP \$MAINPID

# Restart configuration
Restart=always
RestartSec=10
TimeoutStopSec=30

# SECURITY: Systemd hardening
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${PROMETHEUS_DATA} ${PROMETHEUS_LOG}

NoNewPrivileges=true
PrivateTmp=true

ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true

RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
PrivateDevices=true

LockPersonality=true
RestrictRealtime=true
ProtectClock=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=prometheus

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created for Prometheus $major_version.x"
}

# Create default configuration if not exists
create_default_config() {
    local config_file="${PROMETHEUS_CONFIG}/prometheus.yml"

    if [[ -f "$config_file" ]]; then
        log_skip "Configuration already exists: $config_file"
        return 0
    fi

    log_info "Creating default Prometheus configuration..."

    mkdir -p "$PROMETHEUS_CONFIG"
    mkdir -p "$PROMETHEUS_DATA"
    mkdir -p "$PROMETHEUS_LOG"

    cat > "$config_file" << 'EOF'
# Prometheus configuration file
# Generated by observability-stack

global:
  scrape_interval: 15s
  evaluation_interval: 15s

  # External labels for federation and remote write
  external_labels:
    monitor: 'observability-stack'

# Alertmanager configuration (uncomment when configured)
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets:
#           - localhost:9093

# Rule files (uncomment when rules are configured)
# rule_files:
#   - "rules/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node exporter
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):\d+'
        replacement: '${1}'
EOF

    chown -R "$USER_NAME:$GROUP_NAME" "$PROMETHEUS_CONFIG"
    chown -R "$USER_NAME:$GROUP_NAME" "$PROMETHEUS_DATA"
    chmod 755 "$PROMETHEUS_CONFIG"
    chmod 755 "$PROMETHEUS_DATA"

    log_success "Default configuration created"
}

#===============================================================================
# SERVICE MANAGEMENT
#===============================================================================

start_service() {
    log_info "Starting Prometheus service..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start Prometheus service"
        return 0
    fi

    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Wait for service to be ready
    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Prometheus service started"
    else
        log_error "Prometheus service failed to start"
        journalctl -u "$SERVICE_NAME" -n 30 --no-pager
        return 1
    fi
}

# Health check
health_check() {
    local max_attempts="${1:-30}"
    local attempt=0

    log_info "Performing health checks..."

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))

        # Check if service is running
        if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            log_warn "Service not running (attempt $attempt/$max_attempts)"
            sleep 2
            continue
        fi

        # Check health endpoint
        if curl -sf "http://localhost:${PROMETHEUS_PORT}/-/healthy" &>/dev/null; then
            # Check ready endpoint
            if curl -sf "http://localhost:${PROMETHEUS_PORT}/-/ready" &>/dev/null; then
                log_success "Prometheus is healthy and ready"

                # Verify version
                local installed_version
                installed_version=$(detect_current_version)
                log_info "Installed version: $installed_version"

                return 0
            fi
        fi

        log_info "Waiting for Prometheus to be ready (attempt $attempt/$max_attempts)..."
        sleep 2
    done

    log_error "Health check failed after $max_attempts attempts"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    return 1
}

#===============================================================================
# TWO-STAGE UPGRADE ORCHESTRATION
#===============================================================================

# Execute Stage 1 upgrade: 2.48.1 -> 2.55.1
execute_stage1() {
    local current_version="$1"

    log_info "=========================================="
    log_info "STAGE 1: Upgrading to $VERSION_INTERMEDIATE"
    log_info "TSDB v1 -> v2 migration"
    log_info "=========================================="

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute Stage 1 upgrade"
        log_info "[DRY-RUN] Current: $current_version -> Target: $VERSION_INTERMEDIATE"
        return 0
    fi

    # Pre-upgrade checks
    log_info "Running pre-upgrade checks..."

    if ! validate_config; then
        log_error "Configuration validation failed, aborting upgrade"
        return 1
    fi

    if ! check_tsdb_health; then
        log_error "TSDB health check failed, aborting upgrade"
        return 1
    fi

    # Create backup
    local backup_path
    backup_path=$(create_full_backup "stage1" "$current_version")

    # Install intermediate version
    install_binary "$VERSION_INTERMEDIATE"

    # Update service file
    create_service "$VERSION_INTERMEDIATE"

    # Start service and monitor TSDB migration
    start_service

    if ! monitor_tsdb_migration 300; then
        log_error "TSDB migration failed"
        log_warn "Backup available at: $backup_path"
        return 1
    fi

    # Final health check
    if ! health_check 60; then
        log_error "Post-upgrade health check failed"
        log_warn "Backup available at: $backup_path"
        return 1
    fi

    log_success "=========================================="
    log_success "STAGE 1 COMPLETE"
    log_success "Prometheus upgraded to $VERSION_INTERMEDIATE"
    log_success "TSDB v2 migration successful"
    log_success "=========================================="

    return 0
}

# Execute Stage 2 upgrade: 2.55.1 -> 3.8.1
execute_stage2() {
    local current_version="$1"

    log_info "=========================================="
    log_info "STAGE 2: Upgrading to $VERSION_TARGET"
    log_info "Major version upgrade with breaking changes"
    log_info "=========================================="

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute Stage 2 upgrade"
        log_info "[DRY-RUN] Current: $current_version -> Target: $VERSION_TARGET"
        check_deprecated_flags "$VERSION_TARGET"
        return 0
    fi

    # Pre-upgrade checks
    log_info "Running pre-upgrade checks..."

    if ! validate_config; then
        log_error "Configuration validation failed, aborting upgrade"
        return 1
    fi

    if ! check_tsdb_health; then
        log_error "TSDB health check failed, aborting upgrade"
        return 1
    fi

    # Check for deprecated flags
    if ! check_deprecated_flags "$VERSION_TARGET"; then
        log_warn "Deprecated flags detected, will attempt automatic migration"
    fi

    # Create backup
    local backup_path
    backup_path=$(create_full_backup "stage2" "$current_version")

    # Migrate service configuration
    migrate_service_config

    # Install target version
    install_binary "$VERSION_TARGET"

    # Update service file for 3.x
    create_service "$VERSION_TARGET"

    # Start service and monitor
    start_service

    if ! monitor_tsdb_migration 600; then  # Longer timeout for major upgrade
        log_error "Post-upgrade startup failed"
        log_warn "Backup available at: $backup_path"
        return 1
    fi

    # Final health check
    if ! health_check 60; then
        log_error "Post-upgrade health check failed"
        log_warn "Backup available at: $backup_path"
        return 1
    fi

    log_success "=========================================="
    log_success "STAGE 2 COMPLETE"
    log_success "Prometheus upgraded to $VERSION_TARGET"
    log_success "Major version upgrade successful"
    log_success "=========================================="

    return 0
}

#===============================================================================
# ROLLBACK
#===============================================================================

rollback_from_backup() {
    local backup_path="$1"

    if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
        log_error "Invalid backup path: $backup_path"
        return 1
    fi

    log_info "Rolling back from backup: $backup_path"

    # Stop service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    # Restore binaries
    if [[ -f "$backup_path/config-*/prometheus" ]]; then
        cp "$backup_path"/config-*/prometheus "$INSTALL_PATH"
        cp "$backup_path"/config-*/promtool "$PROMTOOL_PATH" 2>/dev/null || true
    fi

    # Restore config
    if [[ -d "$backup_path/config-*/etc-prometheus" ]]; then
        rm -rf "$PROMETHEUS_CONFIG"
        cp -a "$backup_path"/config-*/etc-prometheus "$PROMETHEUS_CONFIG"
    fi

    # Restore service file
    if [[ -f "$backup_path"/config-*/*.service ]]; then
        cp "$backup_path"/config-*/*.service "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi

    # Restore TSDB data if available
    if [[ -d "$backup_path/tsdb-*/data" ]]; then
        log_warn "TSDB data restoration not automatic - manual intervention may be required"
        log_info "TSDB backup location: $backup_path/tsdb-*/data"
    fi

    # Start service
    systemctl start "$SERVICE_NAME"

    log_success "Rollback completed"
}

#===============================================================================
# FRESH INSTALL
#===============================================================================

fresh_install() {
    local version="${MODULE_VERSION:-$VERSION_TARGET}"

    log_info "Performing fresh installation of Prometheus v$version"

    create_user
    create_default_config
    install_binary "$version"
    create_service "$version"
    start_service
    health_check
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Prometheus Installation/Upgrade Script"
    log_info "=========================================="

    # Detect current state
    local current_version
    current_version=$(detect_current_version)

    if [[ -n "$current_version" ]]; then
        log_info "Current Prometheus version: $current_version"
    else
        log_info "Prometheus not currently installed"
    fi

    # Determine what action to take
    local stage
    if [[ "$UPGRADE_STAGE" != "auto" ]]; then
        stage="stage$UPGRADE_STAGE"
        log_info "Forced upgrade stage: $stage"
    else
        stage=$(determine_upgrade_stage "$current_version")
        log_info "Determined upgrade stage: $stage"
    fi

    case "$stage" in
        fresh)
            fresh_install
            ;;

        stage1)
            execute_stage1 "$current_version"
            ;;

        stage2)
            execute_stage2 "$current_version"
            ;;

        current)
            if [[ "$FORCE_MODE" == "true" ]]; then
                log_info "Force mode: reinstalling current version"
                install_binary "$current_version"
                create_service "$current_version"
                start_service
                health_check
            else
                log_skip "Prometheus is already at target version ($current_version)"
                log_info "Use --force to reinstall"
            fi
            ;;

        unknown|*)
            log_warn "Could not determine upgrade path"
            log_info "Current version: $current_version"
            log_info "Intermediate version: $VERSION_INTERMEDIATE"
            log_info "Target version: $VERSION_TARGET"

            if [[ "$FORCE_MODE" == "true" ]]; then
                log_info "Force mode: attempting fresh install of target version"
                fresh_install
            else
                log_error "Please specify --stage=1 or --stage=2 or use --force for fresh install"
                return 1
            fi
            ;;
    esac

    log_success "Prometheus installation/upgrade complete"
}

main "$@"
